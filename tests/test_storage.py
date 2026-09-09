import tempfile
from pathlib import Path
import unittest

from backend.errors import OmaTubeError
from backend.storage import Storage


MEDIA = {
    "videoId": "BaW_jenozKc",
    "source": "youtube",
    "title": "Test",
    "author": "yt-dlp",
    "thumbnailUrl": "https://img.invalid/first.jpg",
    "canonicalUrl": "https://www.youtube.com/watch?v=BaW_jenozKc",
}
SECOND_MEDIA = {
    **MEDIA,
    "videoId": "dQw4w9WgXcQ",
    "title": "Second",
    "thumbnailUrl": "https://img.invalid/second.jpg",
    "canonicalUrl": "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
}


class StorageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.storage = Storage(Path(self.temp.name) / "library.sqlite3")

    def tearDown(self):
        self.storage.close(); self.temp.cleanup()

    def test_duplicate_occurrences_have_distinct_identity_and_order(self):
        playlist = self.storage.create_playlist("Тест")
        first = self.storage.add_playlist_item(playlist["id"], MEDIA)
        second = self.storage.add_playlist_item(playlist["id"], MEDIA)
        self.storage.move_playlist_item(playlist["id"], second["entryId"], first["entryId"])
        opened = self.storage.open_playlist(playlist["id"])
        self.assertEqual([row["entryId"] for row in opened["items"]], [second["entryId"], first["entryId"]])

    def test_playlist_delete_does_not_delete_saved_media_or_history(self):
        self.storage.save_media(MEDIA, True)
        self.storage.add_history(MEDIA)
        playlist = self.storage.create_playlist("Тест")
        self.storage.add_playlist_item(playlist["id"], MEDIA)
        self.storage.delete_playlist(playlist["id"])
        self.assertEqual(self.storage.collection("saved")["items"][0]["videoId"], MEDIA["videoId"])
        self.assertEqual(self.storage.collection("history")["items"][0]["videoId"], MEDIA["videoId"])

    def test_invalid_final_copy_rolls_back_user_playlist(self):
        self.storage.stage_copy_page("operation", [MEDIA, MEDIA], 0)
        with self.assertRaises(OmaTubeError):
            self.storage.finish_copy("operation", "", {"source": "youtube"})
        self.assertEqual(self.storage.collection("playlists")["items"], [])

    def test_local_playlist_cover_follows_first_item(self):
        playlist = self.storage.create_playlist("Обложка")
        first = self.storage.add_playlist_item(playlist["id"], MEDIA)
        self.storage.add_playlist_item(playlist["id"], SECOND_MEDIA)
        listed = self.storage.collection("playlists")["items"][0]
        self.assertEqual(listed["thumbnailUrl"],
                         "https://i.ytimg.com/vi/BaW_jenozKc/hqdefault.jpg")
        self.assertEqual(listed["itemCount"], 2)

        self.storage.remove_playlist_item(playlist["id"], first["entryId"])
        opened = self.storage.open_playlist(playlist["id"])
        self.assertEqual(opened["thumbnailUrl"],
                         "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg")
        self.assertEqual(opened["itemCount"], 1)
        self.assertEqual(opened["items"][0]["media"]["thumbnailUrl"],
                         "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg")

    def test_copied_playlist_keeps_source_cover(self):
        source = {
            "source": "youtube",
            "kind": "playlist",
            "thumbnailUrl": "https://img.invalid/playlist.jpg",
        }
        origin = {"entity": source, "source": "youtube"}
        self.storage.stage_copy_page("cover-copy", [MEDIA], 0)
        playlist = self.storage.finish_copy("cover-copy", "Копия", origin)
        self.assertEqual(playlist["thumbnailUrl"], source["thumbnailUrl"])
        self.assertEqual(
            self.storage.collection("playlists")["items"][0]["thumbnailUrl"],
            source["thumbnailUrl"],
        )

    def test_playlist_and_history_paginate_through_121_rows(self):
        playlist = self.storage.create_playlist("Длинный")
        playlist_entries = []
        for index in range(121):
            item = {
                **MEDIA,
                "videoId": "duplicate" if index < 2 else f"video-{index}",
                "title": f"Row {index}",
            }
            playlist_entries.append(
                self.storage.add_playlist_item(playlist["id"], item)
            )
            self.storage.add_history(item, play_id=f"history-{index}")

        playlist_pages = [
            self.storage.open_playlist(playlist["id"], offset)
            for offset in (0, 50, 100)
        ]
        playlist_rows = [
            row for page in playlist_pages for row in page["items"]
        ]
        self.assertEqual([len(page["items"]) for page in playlist_pages], [50, 50, 21])
        self.assertEqual(
            [page["nextOffset"] for page in playlist_pages],
            [50, 100, None],
        )
        self.assertEqual(len(playlist_rows), 121)
        self.assertNotEqual(
            playlist_rows[0]["entryId"],
            playlist_rows[1]["entryId"],
        )
        self.assertEqual(
            playlist_rows[0]["media"]["videoId"],
            playlist_rows[1]["media"]["videoId"],
        )

        history_pages = [
            self.storage.collection("history", offset)
            for offset in (0, 50, 100)
        ]
        self.assertEqual([len(page["items"]) for page in history_pages], [50, 50, 21])
        self.assertEqual(
            [page["nextOffset"] for page in history_pages],
            [50, 100, None],
        )

        last_entry = playlist_rows[-1]["entryId"]
        self.storage.remove_playlist_item(playlist["id"], last_entry)
        remaining = self.storage.open_playlist(playlist["id"], 100)
        self.assertEqual(len(remaining["items"]), 20)


if __name__ == "__main__": unittest.main()
