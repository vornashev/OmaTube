import asyncio
from pathlib import Path
import tempfile
import unittest

from backend.errors import OmaTubeError
from backend.player import Player
from backend.resolver import ResolvedMedia, ResolvedStream
from backend.storage import Storage


def media(video_id):
    return {"videoId": video_id, "source": "youtube", "title": video_id, "author": "Test", "canonicalUrl": f"https://www.youtube.com/watch?v={video_id}"}


class FakeResolver:
    def __init__(self): self.futures = {}; self.ignore_cancel = set()
    async def resolve(self, video_id):
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
        self.paused = False
        self.video_mode = "audio"
        self.video_error = None
        self.stop_preserve = []
        self.loader_states = []

    async def load(self, media, start=0, paused=False):
        if self.load_error:
            raise self.load_error
        self.loaded.append((media.audio.url, start))
        self.paused = paused
        self.writer = True
    async def set_volume(self, value): pass
    async def set_mute(self, value): pass
    async def pause(self, value): self.paused = value
    async def set_video_loading(self, visible, token="mode"):
        self.loader_states.append((visible, token))
    async def set_video_mode(self, value):
        if self.video_error and value != "audio": raise self.video_error
        self.video_mode = value
    async def seek(self, value): pass
    async def stop_playback(self, preserve_window=False): self.stop_preserve.append(preserve_window)
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
        first.set_result(ResolvedMedia(ResolvedStream("https://stream.invalid/old", {}), 60, True)); await asyncio.sleep(0.01)
        self.assertEqual(self.mpv.loaded, [])
        second.set_result(ResolvedMedia(ResolvedStream("https://stream.invalid/new", {}), 60, True)); await asyncio.sleep(0.01)
        self.assertEqual(self.mpv.loaded[0][0], "https://stream.invalid/new")

    async def test_replace_starts_from_requested_position(self):
        await self.player.replace(media("AAAAAA1"), 125.0); await asyncio.sleep(0)
        self.assertEqual(self.player.position, 125.0)
        self.resolver.futures["AAAAAA1"].set_result(ResolvedMedia(ResolvedStream("https://stream.invalid/a", {}), 600, True)); await asyncio.sleep(0.01)
        self.assertEqual(self.mpv.loaded[-1], ("https://stream.invalid/a", 125.0))

    async def test_enqueued_start_applies_once(self):
        await self.player.replace(media("AAAAAA1")); await asyncio.sleep(0)
        entry = self.player.enqueue(media("BBBBBB2"), "next", 42.0)
        self.assertEqual(entry["startAt"], 42.0)
        await self.player.play_entry(entry["entryId"]); await asyncio.sleep(0)
        self.assertEqual(self.player.position, 42.0)
        self.assertNotIn("startAt", self.player.current)
        await self.player.play_entry(entry["entryId"]); await asyncio.sleep(0)
        self.assertEqual(self.player.position, 0)

    async def test_restore_is_paused_without_resolving(self):
        entry = {"entryId": "entry-1", "media": media("AAAAAA1")}
        self.storage.save_player_state({"queue": [entry], "currentEntryId": "entry-1", "position": 12, "volume": 42, "muted": False, "shuffle": False, "repeat": "off", "videoMode": "floating"})
        restored = Player(self.storage, self.resolver, self.mpv, lambda: None)
        self.assertEqual(restored.state, "paused")
        self.assertEqual(restored.position, 12)
        self.assertEqual(restored.status()["videoMode"], "floating")
        self.assertEqual(self.resolver.futures, {})

    async def test_duplicate_queue_removal_targets_entry_id(self):
        await self.player.replace(media("AAAAAA1")); await asyncio.sleep(0)
        duplicate = self.player.enqueue(media("AAAAAA1"), "end")
        first = self.player.queue[0]["entryId"]
        await self.player.remove(duplicate["entryId"])
        self.assertEqual([row["entryId"] for row in self.player.queue], [first])
    async def test_resolved_metadata_replaces_placeholder(self):
        await self.player.replace(media("AAAAAA1")); await asyncio.sleep(0)
        self.resolver.futures["AAAAAA1"].set_result(ResolvedMedia(
            ResolvedStream("https://stream.invalid/audio", {}), 60, True,
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
            ResolvedMedia(ResolvedStream("https://stream.invalid/audio", {}), 60, True)
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
        player._loaded_generation = player.generation

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
        self.resolver.futures["AAAAAA1"].set_result(ResolvedMedia(
            ResolvedStream("https://stream.invalid/first", {}),
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
        self.resolver.futures["AAAAAA1"].set_result(ResolvedMedia(
            ResolvedStream("https://stream.invalid/recovered", {}),
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

    async def test_seek_loader_waits_for_cache_resume(self):
        entry = {"entryId": "entry-1", "media": media("AAAAAA1")}
        self.player.queue = [entry]
        self.player.current_id = entry["entryId"]
        self.player.state = "playing"
        self.player.can_seek = True
        self.player._loaded_generation = self.player.generation

        await self.player.seek(30)
        self.assertTrue(self.player.status()["buffering"])
        await self.player.handle_mpv_event({
            "event": "property-change", "name": "seeking", "data": False,
        })
        await self.player.handle_mpv_event({
            "event": "property-change", "name": "paused-for-cache", "data": True,
        })
        await asyncio.sleep(0.3)
        self.assertTrue(self.player.status()["buffering"])
        await self.player.handle_mpv_event({
            "event": "property-change", "name": "pause", "data": False,
        })
        await self.player.handle_mpv_event({
            "event": "property-change", "name": "core-idle", "data": True,
        })
        await self.player.handle_mpv_event({
            "event": "property-change", "name": "paused-for-cache", "data": False,
        })
        await asyncio.sleep(0.3)
        self.assertTrue(self.player.status()["buffering"])

        await self.player.handle_mpv_event({
            "event": "property-change", "name": "core-idle", "data": False,
        })
        self.assertTrue(self.player.status()["buffering"])
        await asyncio.sleep(0.3)
        self.assertFalse(self.player.status()["buffering"])

    async def test_video_modes_and_close_keep_paused_track_position(self):
        await self.player.replace(media("AAAAAA1"))
        await self.player.pause()
        await self.player.set_video_mode("tile")
        self.resolver.futures["AAAAAA1"].set_result(ResolvedMedia(
            ResolvedStream("https://stream.invalid/audio", {}), 60, True,
            video=ResolvedStream("https://stream.invalid/video", {}),
        ))
        await self.player.resolve_task
        self.assertEqual(self.player.state, "paused")
        self.assertTrue(self.mpv.paused)
        self.assertEqual(self.mpv.video_mode, "tile")
        self.player.position = 23
        await self.player.set_video_mode("floating")
        await self.player.handle_mpv_event({"event": "client-message", "args": ["omatube-video-closed"]})
        self.assertEqual(self.player.status()["videoMode"], "audio")
        self.assertEqual((self.player.position, self.player.state), (23, "paused"))
        self.assertEqual(len(self.mpv.loaded), 1)
        restored = Player(self.storage, self.resolver, self.mpv, lambda: None)
        self.assertEqual((restored.video_mode, restored.position, restored.state), ("audio", 23, "paused"))

    async def test_failed_video_enable_leaves_audio_playing_and_reports_error(self):
        await self.player.replace(media("AAAAAA1"))
        self.resolver.futures["AAAAAA1"].set_result(ResolvedMedia(
            ResolvedStream("https://stream.invalid/audio", {}), 60, True,
        ))
        await self.player.resolve_task
        self.mpv.video_error = OmaTubeError("video_unavailable", "No video")
        with self.assertRaises(OmaTubeError):
            await self.player.set_video_mode("floating")
        self.assertEqual(self.player.state, "playing")
        self.assertEqual(self.player.video_mode, "audio")
        self.assertEqual(self.player.error["code"], "video_unavailable")

    async def test_latest_mode_wins_while_stale_track_resolves(self):
        self.resolver.ignore_cancel.add("AAAAAA1")
        await self.player.replace(media("AAAAAA1"))
        first = self.resolver.futures["AAAAAA1"]
        await self.player.set_video_mode("floating")
        await self.player.replace(media("BBBBBB2"))
        await self.player.set_video_mode("tile")
        first.set_result(ResolvedMedia(ResolvedStream("https://stream.invalid/old", {}), 60, True))
        self.resolver.futures["BBBBBB2"].set_result(ResolvedMedia(
            ResolvedStream("https://stream.invalid/new", {}), 60, True,
            video=ResolvedStream("https://stream.invalid/video", {}),
        ))
        await self.player.resolve_task
        self.assertEqual(self.mpv.loaded, [("https://stream.invalid/new", 0)])
        self.assertEqual(self.player.video_mode, "tile")
        self.assertEqual(self.mpv.video_mode, "tile")

    async def test_next_preserves_video_window_until_new_track_is_ready(self):
        await self.player.set_video_mode("tile")
        await self.player.replace_many([media("AAAAAA1"), media("BBBBBB2")])
        self.resolver.futures["AAAAAA1"].set_result(ResolvedMedia(
            ResolvedStream("https://stream.invalid/audio-one", {}), 60, True,
            video=ResolvedStream("https://stream.invalid/video-one", {}),
        ))
        await self.player.resolve_task
        await self.player.next()
        await asyncio.sleep(0)
        self.assertTrue(self.mpv.stop_preserve[-1])
        self.assertEqual(self.player.state, "loading")
        await self.player.set_video_mode("audio")
        self.assertEqual(self.mpv.video_mode, "audio")
        await self.player.set_video_mode("tile")
        self.resolver.futures["BBBBBB2"].set_result(ResolvedMedia(
            ResolvedStream("https://stream.invalid/audio-two", {}), 60, True,
            video=ResolvedStream("https://stream.invalid/video-two", {}),
        ))
        await self.player.resolve_task
        self.assertEqual(self.player.video_mode, "tile")
        await self.player.next()
        self.assertFalse(self.mpv.stop_preserve[-1])

    async def test_replace_many_rejects_empty_queue(self):
        with self.assertRaises(OmaTubeError) as caught:
            await self.player.replace_many([])
        self.assertEqual(caught.exception.code, "not_found")


class QueueContextTests(unittest.IsolatedAsyncioTestCase):
    asyncSetUp = PlayerTests.asyncSetUp
    asyncTearDown = PlayerTests.asyncTearDown

    async def test_context_reports_position_in_source_list_and_survives_restore(self):
        context = {"kind": "playlist", "id": "pl-1", "name": "Divinity OST", "offset": 2, "total": 40}
        await self.player.replace_many([media("AAAAAA1"), media("BBBBBB2")], 0, context); await asyncio.sleep(0)
        self.assertEqual(self.player.status()["context"]["index"], 3)
        await self.player.play_entry(self.player.queue[1]["entryId"]); await asyncio.sleep(0)
        self.assertEqual(self.player.status()["context"]["index"], 4)
        restored = Player(self.storage, self.resolver, self.mpv, lambda: None)
        self.assertEqual(restored.status()["context"]["id"], "pl-1")
        await self.player.replace(media("CCCCCC3")); await asyncio.sleep(0)
        self.assertIsNone(self.player.status()["context"])

    async def test_enqueue_reports_position_after_current(self):
        await self.player.replace_many([media("AAAAAA1"), media("BBBBBB2")]); await asyncio.sleep(0)
        self.assertEqual(self.player.enqueue(media("CCCCCC3"), "end", lane="source")["position"], 2)
        self.assertEqual(self.player.enqueue(media("DDDDDD4"), "next")["position"], 1)
        self.assertNotIn("position", self.player.queue[-1])

    async def test_play_first_heads_my_queue_and_keeps_the_interrupted_video_next(self):
        await self.player.replace_many([media("AAAAAA1"), media("BBBBBB2")]); await asyncio.sleep(0)
        self.player.enqueue(media("CCCCCC3"), "end")
        await self.player.play_first(media("DDDDDD4"), 30.0); await asyncio.sleep(0)
        self.assertEqual(self.player.lane, "main")
        self.assertEqual([row["media"]["videoId"] for row in self.player.queue], ["DDDDDD4", "CCCCCC3"])
        self.assertEqual(self.player.current["media"]["videoId"], "DDDDDD4")
        self.assertEqual(self.player.position, 30.0)
        await self.player.play_first(media("EEEEEE5")); await asyncio.sleep(0)
        self.assertEqual([row["media"]["videoId"] for row in self.player.queue], ["EEEEEE5", "DDDDDD4", "CCCCCC3"])
        # Already waiting in My queue: moved to the head, not duplicated.
        await self.player.play_first(media("CCCCCC3")); await asyncio.sleep(0)
        self.assertEqual([row["media"]["videoId"] for row in self.player.queue], ["CCCCCC3", "EEEEEE5", "DDDDDD4"])
        self.assertEqual(self.player.enqueue(media("FFFFFF6"), "next")["position"], 1)
        self.assertEqual(self.player.queue[1]["media"]["videoId"], "FFFFFF6")

    async def test_play_next_into_an_idle_queue_goes_first(self):
        self.player.lane = "main"
        self.player.enqueue(media("AAAAAA1"), "end")
        self.player.enqueue(media("BBBBBB2"), "next")
        self.assertEqual([row["media"]["videoId"] for row in self.player.queue], ["BBBBBB2", "AAAAAA1"])

    async def test_restore_puts_removed_entries_back_in_place(self):
        await self.player.replace_many([media("AAAAAA1"), media("BBBBBB2"), media("CCCCCC3"), media("DDDDDD4")])
        await asyncio.sleep(0)
        rows = [dict(row) for row in self.player.queue]
        await self.player.remove(rows[1]["entryId"]); await self.player.remove(rows[2]["entryId"])
        # Bottom-up: C goes back before D, then B before the restored C.
        self.player.restore([{"entry": rows[2], "beforeEntryId": rows[3]["entryId"]},
                             {"entry": rows[1], "beforeEntryId": rows[2]["entryId"]}])
        self.assertEqual([row["entryId"] for row in self.player.queue], [row["entryId"] for row in rows])
        self.player.restore([{"entry": rows[1], "beforeEntryId": None}])
        self.assertEqual(len(self.player.queue), 4)
        with self.assertRaises(OmaTubeError):
            self.player.restore([{"entry": {"entryId": "x", "media": {}}}])

    async def test_cancel_load_keeps_entry_and_play_retries(self):
        await self.player.replace(media("AAAAAA1")); await asyncio.sleep(0)
        await self.player.cancel_load(); await asyncio.sleep(0)
        self.assertEqual(self.player.state, "paused")
        self.assertEqual(self.player.current["media"]["videoId"], "AAAAAA1")
        self.resolver.futures.clear()
        await self.player.play(); await asyncio.sleep(0)
        self.assertEqual(self.player.state, "loading")
        self.assertIn("AAAAAA1", self.resolver.futures)

    async def test_upcoming_skip_segment_can_be_kept_once(self):
        self.player.sponsor_actions = {"sponsor": "skip"}
        self.player.segments = [{"id": "seg", "start": 100.0, "end": 130.0, "category": "sponsor"}]
        self.player.state = "playing"; self.player.position = 98.0
        self.assertEqual(self.player.sponsor_status()["upcoming"]["id"], "seg")
        self.player.sponsor_keep("seg")
        self.assertIsNone(self.player.sponsor_status()["upcoming"])
        self.player.position = 110.0; self.player.can_seek = True
        await self.player._check_segments(110.0)
        self.assertNotIn("seg", self.player.sponsor_done)


class LaneTests(unittest.IsolatedAsyncioTestCase):
    asyncSetUp = PlayerTests.asyncSetUp
    asyncTearDown = PlayerTests.asyncTearDown

    async def resolve(self, video_id, duration=600):
        self.resolver.futures[video_id].set_result(ResolvedMedia(ResolvedStream(f"https://stream.invalid/{video_id}", {}), duration, True))
        await asyncio.sleep(0.01)

    def ids(self, lane):
        return [row["media"]["videoId"] for row in self.player.lanes[lane]["queue"]]

    async def test_play_fills_now_playing_and_keeps_my_queue(self):
        saved = self.player.enqueue(media("QQQQQQ1"), "end")
        self.assertEqual(saved["lane"], "main")
        await self.player.replace_many([media("AAAAAA1"), media("BBBBBB2")]); await asyncio.sleep(0)
        self.assertEqual(self.player.lane, "source")
        self.assertEqual(self.ids("main"), ["QQQQQQ1"])
        self.player.enqueue(media("CCCCCC3"), "next")
        self.assertEqual(self.ids("source"), ["AAAAAA1", "CCCCCC3", "BBBBBB2"])
        self.assertEqual(self.player.status()["lanes"]["main"]["count"], 1)

    async def test_switch_to_my_queue_resumes_saved_position(self):
        self.player.enqueue(media("QQQQQQ1"), "end")
        self.storage.save_progress("QQQQQQ1", 760.0, 1445.0)
        await self.player.replace(media("AAAAAA1")); await asyncio.sleep(0)
        await self.player.switch_lane("main"); await asyncio.sleep(0)
        self.assertEqual(self.player.lane, "main")
        await self.resolve("QQQQQQ1", 1445)
        self.assertEqual(self.mpv.loaded[-1], ("https://stream.invalid/QQQQQQ1", 760.0))
        await self.player.switch_lane("source", play=False)
        self.assertEqual((self.player.lane, self.player.state), ("source", "paused"))
        self.assertEqual(self.player.current["media"]["videoId"], "AAAAAA1")

    async def test_finished_item_leaves_my_queue_and_can_be_undone(self):
        for video_id in ("QQQQQQ1", "QQQQQQ2"): self.player.enqueue(media(video_id), "end")
        await self.player.switch_lane("main"); await asyncio.sleep(0)
        await self.resolve("QQQQQQ1")
        await self.player.handle_mpv_event({"event": "end-file", "reason": "eof"}); await asyncio.sleep(0)
        self.assertEqual(self.ids("main"), ["QQQQQQ2"])
        notice = self.player.status()["notice"]
        self.assertEqual((notice["kind"], notice["title"]), ("finished", "QQQQQQ1"))
        self.assertEqual(self.player.current["media"]["videoId"], "QQQQQQ2")
        self.player.restore(notice["entries"], "main")
        self.assertEqual(self.ids("main"), ["QQQQQQ1", "QQQQQQ2"])

    async def test_skipping_unfinished_item_keeps_it_in_my_queue(self):
        for video_id in ("QQQQQQ1", "QQQQQQ2"): self.player.enqueue(media(video_id), "end")
        await self.player.switch_lane("main"); await asyncio.sleep(0)
        await self.resolve("QQQQQQ1")
        self.player.position = 120.0
        await self.player.next(); await asyncio.sleep(0)
        self.assertEqual(self.ids("main"), ["QQQQQQ1", "QQQQQQ2"])
        self.player.position = 590.0; self.player.duration = 600.0
        await self.player.next(); await asyncio.sleep(0)
        self.assertEqual(self.ids("main"), ["QQQQQQ1"])

    async def test_end_of_playlist_continues_with_my_queue(self):
        self.player.enqueue(media("QQQQQQ1"), "end")
        await self.player.replace_many([media("AAAAAA1")], 0, {"kind": "playlist", "id": "pl", "name": "Mix"}); await asyncio.sleep(0)
        await self.resolve("AAAAAA1")
        await self.player.handle_mpv_event({"event": "end-file", "reason": "eof"}); await asyncio.sleep(0)
        self.assertEqual(self.player.lane, "main")
        self.assertEqual(self.player.status()["notice"]["reason"], "sourceEnded")
        self.assertEqual(self.player.lanes["source"]["currentEntryId"], self.player.lanes["source"]["queue"][0]["entryId"])

    async def test_my_queue_ending_resumes_the_paused_playlist(self):
        await self.player.replace_many([media("AAAAAA1"), media("BBBBBB2")], 0, {"kind": "playlist", "id": "pl", "name": "Mix"})
        await asyncio.sleep(0); await self.resolve("AAAAAA1")
        await self.player.next(); await asyncio.sleep(0); await self.resolve("BBBBBB2")
        self.player.position = 161.0
        await self.player.play_first(media("XXXXXX1")); await asyncio.sleep(0)
        self.assertEqual(self.player.lane, "main")
        await self.resolve("XXXXXX1")
        await self.player.handle_mpv_event({"event": "end-file", "reason": "eof"}); await asyncio.sleep(0)
        self.assertEqual(self.player.lane, "source")
        self.assertEqual(self.player.current["media"]["videoId"], "BBBBBB2")
        self.assertEqual(self.player.position, 161.0)
        notice = self.player.status()["notice"]
        self.assertEqual((notice["reason"], notice["name"]), ("queueEnded", "Mix"))
        self.assertEqual(notice["entries"][0]["entry"]["media"]["videoId"], "XXXXXX1")  # the toast can restore it
        self.assertEqual(self.ids("main"), [])

    async def test_manual_next_on_last_queue_item_also_returns_to_the_playlist(self):
        await self.player.replace_many([media("AAAAAA1")], 0, {"kind": "playlist", "id": "pl", "name": "Mix"}); await asyncio.sleep(0)
        await self.player.play_first(media("XXXXXX1")); await asyncio.sleep(0); await self.resolve("XXXXXX1")
        self.player.position = 30.0
        await self.player.next(); await asyncio.sleep(0)
        self.assertEqual((self.player.lane, self.player.current["media"]["videoId"]), ("source", "AAAAAA1"))
        self.assertEqual(self.ids("main"), ["XXXXXX1"])  # not watched, so it stays

    async def test_a_playlist_played_to_the_end_does_not_come_back(self):
        self.player.enqueue(media("QQQQQQ1"), "end")
        await self.player.replace_many([media("AAAAAA1")], 0, {"kind": "playlist", "id": "pl", "name": "Mix"}); await asyncio.sleep(0)
        await self.resolve("AAAAAA1")
        await self.player.handle_mpv_event({"event": "end-file", "reason": "eof"}); await asyncio.sleep(0)
        self.assertEqual(self.player.lane, "main")
        self.assertTrue(Player(self.storage, self.resolver, self.mpv, lambda: None).lanes["source"]["ended"])  # survives a restart
        await self.resolve("QQQQQQ1")
        await self.player.handle_mpv_event({"event": "end-file", "reason": "eof"}); await asyncio.sleep(0)
        self.assertEqual((self.player.lane, self.player.state), ("main", "idle"))
        await self.player.replace_many([media("BBBBBB2")]); await asyncio.sleep(0)
        self.assertFalse(self.player.lanes["source"]["ended"])

    async def test_remove_by_entry_id_finds_the_inactive_lane(self):
        saved = self.player.enqueue(media("QQQQQQ1"), "end")
        await self.player.replace(media("AAAAAA1")); await asyncio.sleep(0)
        await self.player.remove(saved["entryId"])
        self.assertEqual(self.ids("main"), [])
        self.assertEqual(self.ids("source"), ["AAAAAA1"])

    async def test_lanes_survive_restart_and_old_snapshots_migrate(self):
        self.player.enqueue(media("QQQQQQ1"), "end")
        await self.player.replace(media("AAAAAA1")); await asyncio.sleep(0)
        restored = Player(self.storage, self.resolver, self.mpv, lambda: None)
        self.assertEqual(restored.lane, "source")
        self.assertEqual([row["media"]["videoId"] for row in restored.lanes["main"]["queue"]], ["QQQQQQ1"])
        entry = {"entryId": "entry-1", "media": media("BBBBBB2")}
        self.storage.save_player_state({"queue": [entry], "currentEntryId": "entry-1", "position": 12})
        self.assertEqual(Player(self.storage, self.resolver, self.mpv, lambda: None).lane, "main")
        self.storage.save_player_state({"queue": [entry], "currentEntryId": "entry-1", "context": {"kind": "playlist", "id": "pl"}})
        legacy = Player(self.storage, self.resolver, self.mpv, lambda: None)
        self.assertEqual((legacy.lane, legacy.current_id), ("source", "entry-1"))


if __name__ == "__main__": unittest.main()
