import asyncio
from pathlib import Path
import tempfile
import unittest

from backend.errors import OmaTubeError
from backend.player import Player
from backend.resolver import ResolvedAudio
from backend.storage import Storage


def media(video_id):
    return {"videoId": video_id, "source": "youtube", "title": video_id, "author": "Test", "canonicalUrl": f"https://www.youtube.com/watch?v={video_id}"}


class FakeResolver:
    def __init__(self): self.futures = {}; self.ignore_cancel = set()
    async def resolve_audio(self, video_id):
        future = asyncio.get_running_loop().create_future(); self.futures[video_id] = future
        try:
            return await asyncio.shield(future)
        except asyncio.CancelledError:
            if video_id not in self.ignore_cancel: raise
            return await future


class FakeMpv:
    def __init__(self):
        self.loaded = []
        self.writer = None
        self.load_error = None

    async def load(self, audio, start=0):
        if self.load_error:
            raise self.load_error
        self.loaded.append((audio.url, start))
        self.writer = True
    async def set_volume(self, value): pass
    async def set_mute(self, value): pass
    async def pause(self, value): pass
    async def seek(self, value): pass
    async def stop_playback(self): pass
    async def stop(self): pass


class PlayerTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.storage = Storage(Path(self.temp.name) / "db.sqlite3")
        self.resolver = FakeResolver(); self.mpv = FakeMpv(); self.player = Player(self.storage, self.resolver, self.mpv, lambda: None)

    async def asyncTearDown(self):
        if self.player.resolve_task: self.player.resolve_task.cancel()
        if self.player.history_timer: self.player.history_timer.cancel()
        await asyncio.gather(*(task for task in (self.player.resolve_task, self.player.history_timer) if task), return_exceptions=True)
        self.storage.close(); self.temp.cleanup()

    async def test_stale_resolve_cannot_replace_new_selection(self):
        self.resolver.ignore_cancel.add("AAAAAA1")
        await self.player.replace(media("AAAAAA1")); await asyncio.sleep(0)
        first = self.resolver.futures["AAAAAA1"]
        await self.player.replace(media("BBBBBB2")); await asyncio.sleep(0)
        second = self.resolver.futures["BBBBBB2"]
        first.set_result(ResolvedAudio("https://stream.invalid/old", {}, 60, True)); await asyncio.sleep(0.01)
        self.assertEqual(self.mpv.loaded, [])
        second.set_result(ResolvedAudio("https://stream.invalid/new", {}, 60, True)); await asyncio.sleep(0.01)
        self.assertEqual(self.mpv.loaded[0][0], "https://stream.invalid/new")

    async def test_restore_is_paused_without_resolving(self):
        entry = {"entryId": "entry-1", "media": media("AAAAAA1")}
        self.storage.save_player_state({"queue": [entry], "currentEntryId": "entry-1", "position": 12, "volume": 42, "muted": False, "shuffle": False, "repeat": "off"})
        restored = Player(self.storage, self.resolver, self.mpv, lambda: None)
        self.assertEqual(restored.state, "paused")
        self.assertEqual(restored.position, 12)
        self.assertEqual(self.resolver.futures, {})

    async def test_duplicate_queue_removal_targets_entry_id(self):
        await self.player.replace(media("AAAAAA1")); await asyncio.sleep(0)
        duplicate = self.player.enqueue(media("AAAAAA1"), "end")
        first = self.player.queue[0]["entryId"]
        await self.player.remove(duplicate["entryId"])
        self.assertEqual([row["entryId"] for row in self.player.queue], [first])
    async def test_resolved_metadata_replaces_placeholder(self):
        await self.player.replace(media("AAAAAA1")); await asyncio.sleep(0)
        self.resolver.futures["AAAAAA1"].set_result(ResolvedAudio(
            "https://stream.invalid/audio", {}, 60, True,
            title="Resolved title", author="Resolved author",
            thumbnail_url="https://img.invalid/cover.jpg",
            canonical_url="https://www.youtube.com/watch?v=AAAAAA1",
            view_count=1200345, like_count=45678,
        ))
        await asyncio.sleep(0.01)
        current = self.player.current["media"]
        self.assertEqual((current["title"], current["author"], current["thumbnailUrl"]),
                         ("Resolved title", "Resolved author", "https://img.invalid/cover.jpg"))
        self.assertEqual((current["viewCount"], current["likeCount"]), (1200345, 45678))

    async def test_unexpected_playback_failure_leaves_recoverable_error_state(self):
        self.player.duration = 123
        self.player.can_seek = True
        self.mpv.load_error = RuntimeError("broken IPC")
        await self.player.replace(media("AAAAAA1"))
        self.assertIsNone(self.player.duration)
        self.assertFalse(self.player.can_seek)
        self.resolver.futures["AAAAAA1"].set_result(
            ResolvedAudio("https://stream.invalid/audio", {}, 60, True)
        )
        await asyncio.sleep(0.01)
        self.assertEqual(self.player.state, "error")
        self.assertEqual(self.player.error["code"], "playback_error")

    async def test_shuffle_does_not_replay_items_before_cycle_end(self):
        self.player.queue = [
            {"entryId": "a", "media": media("AAAAAA1")},
            {"entryId": "b", "media": media("BBBBBB2")},
            {"entryId": "c", "media": media("CCCCCC3")},
        ]
        self.player.current_id = "a"; self.player.shuffle = True
        self.player.shuffle_order = ["a", "b", "c"]
        self.assertEqual(self.player._next_id(), "b")
        self.player.current_id = "b"
        self.assertEqual(self.player._next_id(), "c")
        self.player.current_id = "c"
        self.assertIsNone(self.player._next_id())

    async def test_short_track_history_notifies_collection_revision_callback(self):
        notifications = []
        player = Player(
            self.storage,
            self.resolver,
            self.mpv,
            lambda: None,
            lambda: notifications.append("changed"),
        )
        player.queue = [{"entryId": "entry", "media": media("AAAAAA1")}]
        player.current_id = "entry"
        player.state = "playing"
        player.duration = 4

        await player.handle_mpv_event({"event": "end-file", "reason": "eof"})

        self.assertEqual(notifications, ["changed"])
        self.assertEqual(
            self.storage.collection("history")["items"][0]["videoId"],
            "AAAAAA1",
        )

    async def test_replace_many_is_atomic_and_restores_complete_queue(self):
        rows = [media(f"video-{index}") for index in range(1000)]
        rows[501] = media("video-500")
        await self.player.replace_many(rows)
        await asyncio.sleep(0)

        self.assertEqual(
            [entry["media"]["videoId"] for entry in self.player.queue],
            [entry["videoId"] for entry in rows],
        )
        self.assertEqual(self.player.current, self.player.queue[0])
        self.assertNotEqual(
            self.player.queue[500]["entryId"],
            self.player.queue[501]["entryId"],
        )

        if self.player.resolve_task:
            self.player.resolve_task.cancel()
            await asyncio.gather(self.player.resolve_task, return_exceptions=True)
        restored = Player(self.storage, self.resolver, self.mpv, lambda: None)
        self.assertEqual(len(restored.queue), 1000)
        self.assertEqual(restored.state, "paused")
        self.assertEqual(
            [entry["media"]["videoId"] for entry in restored.queue],
            [entry["videoId"] for entry in rows],
        )

        previous_queue = self.player.queue
        previous_current = self.player.current_id
        with self.assertRaises(OmaTubeError) as caught:
            await self.player.replace_many([media("valid"), {}])
        self.assertEqual(caught.exception.code, "invalid_request")
        self.assertIs(self.player.queue, previous_queue)
        self.assertEqual(self.player.current_id, previous_current)

    async def test_disconnect_preserves_track_and_play_recovers_position(self):
        await self.player.replace(media("AAAAAA1"))
        await asyncio.sleep(0)
        self.resolver.futures["AAAAAA1"].set_result(ResolvedAudio(
            "https://stream.invalid/first",
            {},
            120,
            True,
        ))
        await asyncio.sleep(0.01)
        self.player.position = 37
        queue = self.player.queue
        current_id = self.player.current_id

        await self.player.handle_mpv_event({"event": "omatube-disconnected"})

        self.assertEqual(self.player.state, "error")
        self.assertEqual(self.player.error["code"], "mpv_disconnected")
        self.assertIs(self.player.queue, queue)
        self.assertEqual(self.player.current_id, current_id)
        self.assertEqual(self.player.position, 37)

        await self.player.play()
        await asyncio.sleep(0)
        self.resolver.futures["AAAAAA1"].set_result(ResolvedAudio(
            "https://stream.invalid/recovered",
            {},
            120,
            True,
        ))
        await asyncio.sleep(0.01)
        self.assertEqual(self.mpv.loaded[-1], (
            "https://stream.invalid/recovered",
            37,
        ))
        self.assertEqual(self.player.state, "playing")
        self.assertIsNone(self.player.error)

    async def test_replace_many_rejects_empty_queue(self):
        with self.assertRaises(OmaTubeError) as caught:
            await self.player.replace_many([])
        self.assertEqual(caught.exception.code, "not_found")


if __name__ == "__main__": unittest.main()
