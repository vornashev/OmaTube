import asyncio
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import AsyncMock, patch

from backend.errors import OmaTubeError
from backend.main import Backend


class FakeCatalog:
    def __init__(self) -> None:
        self.calls: list[tuple[str, dict]] = []
        self.stopped = False

    async def request(self, method: str, params: dict, timeout: float = 45) -> dict:
        self.calls.append((method, params))
        return {"released": True}

    async def stop(self) -> None:
        self.stopped = True


class BlockingCopyCatalog(FakeCatalog):
    def __init__(self) -> None:
        super().__init__()
        self.next_started = asyncio.Event()

    async def request(self, method: str, params: dict, timeout: float = 45) -> dict:
        self.calls.append((method, params))
        if method == "open":
            return {
                "items": [{"videoId": "first", "source": "youtube"}],
                "nextCursor": "next-page",
            }
        if method == "next":
            self.next_started.set()
            await asyncio.Future()
        return {"released": True}

class PagingCatalog(FakeCatalog):
    def __init__(self) -> None:
        super().__init__()
        self.next_started = asyncio.Event()
        self.release_next = asyncio.Event()

    async def request(self, method: str, params: dict, timeout: float = 45) -> dict:
        self.calls.append((method, params))
        if method == "next":
            self.next_started.set()
            await self.release_next.wait()
            return {"items": [{"videoId": "next"}], "nextCursor": None}
        return {"released": True}


class BlockingResolver:
    def __init__(self) -> None:
        self.release = asyncio.Event()

    async def resolve(self, _video_id: str):
        await self.release.wait()

class BackendTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        root = Path(self.temporary.name)
        self.environment = patch.dict(
            os.environ,
            {
                "XDG_RUNTIME_DIR": str(root / "run"),
                "XDG_DATA_HOME": str(root / "data"),
                "XDG_CONFIG_HOME": str(root / "config"),
            },
        )
        self.environment.start()
        (root / "run").mkdir()
        self.backend = Backend(Path(__file__).resolve().parents[1])
        self.backend.catalog = FakeCatalog()
        self.backend_stopped = False

    async def asyncTearDown(self) -> None:
        if not self.backend_stopped:
            await self.backend.stop()
        self.environment.stop()
        self.temporary.cleanup()

    @staticmethod
    def terminal_record(operation_id: str, view_id: str) -> dict:
        return {
            "operationId": operation_id,
            "kind": "search",
            "request": {},
            "state": "done",
            "startedAt": 1.0,
            "finishedAt": 2.0,
            "processed": 0,
            "result": {"viewId": view_id},
            "error": None,
        }

    async def test_youtube_auth_status_and_import_operation(self):
        self.backend.youtube_auth.path.write_text(
            "# Netscape HTTP Cookie File\n"
            ".youtube.com\tTRUE\t/\tTRUE\t0\tSAPISID\ttest\n",
            encoding="utf-8",
        )
        self.backend.youtube_auth.path.chmod(0o600)
        self.assertTrue(self.backend.status()["youtubeAuth"]["authenticated"])
        imported = {
            "configured": True, "authenticated": True,
            "cookieCount": 1, "browser": "chromium",
        }
        with patch.object(
            self.backend.youtube_auth,
            "import_from_browser",
            AsyncMock(return_value=imported),
        ) as run:
            accepted = await self.backend.command({
                "command": "youtube_auth_import", "browser": "chromium",
            })
            await self.backend.operations[accepted["operationId"]]["task"]
        run.assert_awaited_once_with("chromium")
        self.assertEqual(
            self.backend.operations[accepted["operationId"]]["result"],
            imported,
        )

    async def test_video_mode_accepts_slow_open_and_reports_failure_in_details(self):
        started = asyncio.Event()
        release = asyncio.Event()

        async def open_video(_mode):
            started.set()
            await release.wait()
            raise OmaTubeError("video_unavailable", "Video stream unavailable")

        with patch.object(self.backend.player, "set_video_mode", open_video):
            accepted = await asyncio.wait_for(
                self.backend.command({"command": "video_mode", "value": "floating"}), 1,
            )
            await asyncio.wait_for(started.wait(), 1)
            operation_id = accepted["operationId"]
            details = await self.backend.command({"command": "details"})
            record = next(row for row in details["operations"] if row["operationId"] == operation_id)
            self.assertEqual(record["state"], "running")
            release.set()
            await self.backend.operations[operation_id]["task"]
            details = await self.backend.command({"command": "details"})
            record = next(row for row in details["operations"] if row["operationId"] == operation_id)
            self.assertEqual(record["state"], "failed")
            self.assertEqual(record["error"]["code"], "video_unavailable")

    async def test_video_quality_accepts_supported_values_and_rejects_unknown_height(self):
        accepted = await self.backend.command({"command": "video_quality", "value": 720})
        await self.backend.operations[accepted["operationId"]]["task"]
        self.assertEqual(self.backend.status()["preferences"]["videoQuality"], 720)
        with self.assertRaises(OmaTubeError) as raised:
            await self.backend.command({"command": "video_quality", "value": 800})
        self.assertEqual(raised.exception.code, "invalid_request")

    async def test_details_omits_unchanged_sections_and_detects_new_session(self):
        self.backend.player.queue = [{"entryId": "one", "media": {"videoId": "one"}}]
        self.backend.player.queue_revision = 4
        self.backend.catalog_revision = 7
        self.backend.views["view"] = {"viewId": "view", "type": "search", "items": []}
        self.backend.operations["operation"] = self.terminal_record("operation", "view")

        full = await self.backend.command({"command": "details"})
        self.assertIn("queue", full)
        self.assertIn("views", full)
        self.assertIn("operations", full)
        known = {
            "backendSessionId": full["backendSessionId"],
            "queueRevision": full["queueRevision"],
            "catalogRevision": full["catalogRevision"],
        }

        unchanged = await self.backend.command(
            {"command": "details", "knownRevisions": known}
        )
        self.assertIn("state", unchanged)
        self.assertNotIn("queue", unchanged)
        self.assertNotIn("views", unchanged)
        self.assertNotIn("operations", unchanged)

        retention_changed = await self.backend.command(
            {
                "command": "details",
                "knownRevisions": known,
                "retainedOperationIds": ["operation"],
            }
        )
        self.assertIn("views", retention_changed)
        self.assertIn("operations", retention_changed)

        self.backend.player.position = 42
        position_only = await self.backend.command(
            {"command": "details", "knownRevisions": known}
        )
        self.assertEqual(position_only["position"], 42)
        self.assertNotIn("queue", position_only)
        self.assertNotIn("views", position_only)

        self.backend.player.queue_revision += 1
        queue_changed = await self.backend.command(
            {"command": "details", "knownRevisions": known}
        )
        self.assertIn("queue", queue_changed)
        self.assertNotIn("views", queue_changed)

        restarted = await self.backend.command(
            {
                "command": "details",
                "knownRevisions": {
                    **known,
                    "backendSessionId": "different-session",
                    "queueRevision": self.backend.player.queue_revision,
                    "catalogRevision": self.backend.catalog_revision,
                },
            }
        )
        self.assertIn("queue", restarted)
        self.assertIn("views", restarted)
        self.assertIn("operations", restarted)

        second = Backend(Path(__file__).resolve().parents[1])
        try:
            second.player.queue_revision = self.backend.player.queue_revision
            second.catalog_revision = self.backend.catalog_revision
            self.assertNotEqual(second.backend_session_id, self.backend.backend_session_id)
        finally:
            await second.stop()

    async def test_details_rejects_invalid_conditional_fields(self):
        invalid_requests = (
            {"knownRevisions": []},
            {"knownRevisions": {"queueRevision": "1"}},
            {"knownRevisions": {"catalogRevision": True}},
            {"retainedOperationIds": "operation"},
            {"retainedOperationIds": [1]},
        )
        for invalid in invalid_requests:
            with self.subTest(invalid=invalid):
                with self.assertRaises(OmaTubeError) as caught:
                    self.backend.details(invalid)
                self.assertEqual(caught.exception.code, "invalid_request")

    async def test_view_results_are_references_and_terminal_tasks_are_removed(self):
        async def search() -> dict:
            view = {
                "viewId": "view",
                "type": "search",
                "items": [{"videoId": "video"}],
            }
            self.backend.views["view"] = view
            return view

        accepted = self.backend._operation("search", {"command": "search"}, search)
        operation_id = accepted["operationId"]
        task = self.backend.operations[operation_id]["task"]
        await task

        record = self.backend.operations[operation_id]
        self.assertEqual(record["state"], "done")
        self.assertEqual(record["result"], {"viewId": "view"})
        self.assertNotIn("task", record)
        self.assertEqual(self.backend.views["view"]["items"][0]["videoId"], "video")

    async def test_retention_bounds_operations_views_and_releases_cursors(self):
        async def create_view(label: str) -> str:
            async def runner() -> dict:
                view_id = f"view-{label}"
                view = {
                    "viewId": view_id,
                    "type": "entity" if label == "entity" else "search",
                    "items": [],
                    "nextCursor": f"cursor-{label}",
                    "sections": {
                        "more": {"items": [], "nextCursor": f"section-{label}"}
                    },
                }
                self.backend.views[view_id] = view
                return view

            accepted = self.backend._operation("search", {"command": "search"}, runner)
            operation_id = accepted["operationId"]
            await self.backend.operations[operation_id]["task"]
            return operation_id

        old_search = await create_view("old-search")
        old_entity = await create_view("entity")
        self.backend.details({"retainedOperationIds": [old_search, old_entity]})

        for index in range(100):
            await create_view(str(index))

        retained = {old_search, old_entity}
        terminal_others = [
            operation_id
            for operation_id, record in self.backend.operations.items()
            if operation_id not in retained and record["state"] != "running"
        ]
        self.assertLessEqual(len(terminal_others), 32)
        self.assertTrue(retained.issubset(self.backend.operations))
        self.assertIn("view-old-search", self.backend.views)
        self.assertIn("view-entity", self.backend.views)
        self.assertLessEqual(len(self.backend.views), 34)

        await self.backend.stop()
        self.backend_stopped = True
        released = {
            params["cursor"]
            for method, params in self.backend.catalog.calls
            if method == "release"
        }
        self.assertIn("cursor-0", released)
        self.assertIn("section-0", released)

    async def test_running_continuation_keeps_its_view_reachable(self):
        self.backend.views["continued"] = {
            "viewId": "continued",
            "type": "search",
            "items": [],
            "nextCursor": "cursor",
        }
        blocker = asyncio.Future()

        async def continue_view() -> dict:
            await blocker
            return self.backend.views["continued"]

        accepted = self.backend._operation(
            "search_more",
            {"command": "search_more", "viewId": "continued"},
            continue_view,
        )
        for index in range(40):
            operation_id = f"old-{index}"
            self.backend.operations[operation_id] = self.terminal_record(
                operation_id, f"missing-{index}"
            )
        self.backend._prune_operations()
        self.assertIn("continued", self.backend.views)

        blocker.set_result(None)
        await self.backend.operations[accepted["operationId"]]["task"]

    async def test_shutdown_waits_for_copy_rollback_before_storage_close(self):
        catalog = BlockingCopyCatalog()
        self.backend.catalog = catalog
        staging_at_close: list[int] = []
        original_close = self.backend.storage.close

        def checked_close() -> None:
            count = self.backend.storage.db.execute(
                "SELECT COUNT(*) FROM copy_staging"
            ).fetchone()[0]
            staging_at_close.append(count)
            original_close()

        self.backend.storage.close = checked_close
        revision_before = self.backend.catalog_revision
        accepted = await self.backend.command(
            {
                "command": "playlist_copy",
                "entity": {"kind": "playlist", "source": "youtube", "id": "source"},
                "name": "copy",
            }
        )
        await asyncio.wait_for(catalog.next_started.wait(), 0.5)
        self.assertGreater(self.backend.catalog_revision, revision_before)
        self.assertEqual(
            self.backend.operations[accepted["operationId"]]["processed"], 1
        )

        await self.backend.stop()
        self.backend_stopped = True
        self.assertEqual(staging_at_close, [0])
        self.assertTrue(catalog.stopped)


    async def test_simultaneous_more_requests_share_one_operation_and_append(self):
        catalog = PagingCatalog()
        self.backend.catalog = catalog
        self.backend.views["view"] = {
            "viewId": "view",
            "type": "search",
            "items": [{"videoId": "first"}],
            "nextCursor": "cursor",
        }

        first = await self.backend.command(
            {"command": "search_more", "viewId": "view"}
        )
        await asyncio.wait_for(catalog.next_started.wait(), 0.5)
        second = await self.backend.command(
            {"command": "search_more", "viewId": "view"}
        )
        self.assertEqual(first["operationId"], second["operationId"])

        catalog.release_next.set()
        task = self.backend.operations[first["operationId"]]["task"]
        await task
        self.assertEqual(
            self.backend.views["view"]["items"],
            [{"videoId": "first"}, {"videoId": "next"}],
        )
        next_calls = [call for call in catalog.calls if call[0] == "next"]
        self.assertEqual(len(next_calls), 1)

    async def test_failed_storage_mutation_does_not_advance_collection_revision(self):
        revision = self.backend.collection_revision
        with self.assertRaises(OmaTubeError):
            await self.backend.command({"command": "playlist_create", "name": ""})
        self.assertEqual(self.backend.collection_revision, revision)

    async def test_play_view_replaces_queue_with_selected_suffix(self):
        rows = [
            {"videoId": f"video-{index}", "source": "youtube"}
            for index in range(1000)
        ]
        rows[701]["videoId"] = "duplicate"
        rows[702]["videoId"] = "duplicate"
        self.backend.views["view"] = {
            "viewId": "view",
            "type": "search",
            "items": rows,
        }
        self.backend.player.resolver = BlockingResolver()

        await self.backend._play_view("view", "video-700")

        queue = self.backend.player.queue
        self.assertEqual(len(queue), 300)
        self.assertEqual(
            [entry["media"]["videoId"] for entry in queue],
            [entry["videoId"] for entry in rows[700:]],
        )
        self.assertEqual(self.backend.player.current_id, queue[0]["entryId"])
        self.assertNotEqual(queue[1]["entryId"], queue[2]["entryId"])
        if self.backend.player.resolve_task:
            self.backend.player.resolve_task.cancel()
            await asyncio.gather(
                self.backend.player.resolve_task,
                return_exceptions=True,
            )

if __name__ == "__main__":
    unittest.main()
