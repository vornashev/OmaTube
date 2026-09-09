import asyncio
from typing import Any

from dbus_next import Variant
from dbus_next.aio import MessageBus
from dbus_next.constants import PropertyAccess
from dbus_next.service import ServiceInterface, dbus_property, method, signal


class MprisRoot(ServiceInterface):
    def __init__(self) -> None: super().__init__("org.mpris.MediaPlayer2")

    @method()
    def Raise(self): pass

    @method()
    def Quit(self): pass

    @dbus_property(access=PropertyAccess.READ)
    def CanQuit(self) -> "b": return False

    @dbus_property(access=PropertyAccess.READ)
    def CanRaise(self) -> "b": return False

    @dbus_property(access=PropertyAccess.READ)
    def HasTrackList(self) -> "b": return False

    @dbus_property(access=PropertyAccess.READ)
    def Identity(self) -> "s": return "OmaTube"

    @dbus_property(access=PropertyAccess.READ)
    def DesktopEntry(self) -> "s": return ""

    @dbus_property(access=PropertyAccess.READ)
    def SupportedUriSchemes(self) -> "as": return ["https"]

    @dbus_property(access=PropertyAccess.READ)
    def SupportedMimeTypes(self) -> "as": return []


class MprisPlayer(ServiceInterface):
    def __init__(self, player: Any) -> None:
        super().__init__("org.mpris.MediaPlayer2.Player"); self.player = player

    @method()
    async def Next(self): await self.player.next(True)

    @method()
    async def Previous(self): await self.player.previous()

    @method()
    async def Pause(self): await self.player.pause()

    @method()
    async def PlayPause(self):
        if self.player.state == "playing": await self.player.pause()
        else: await self.player.play()

    @method()
    async def Stop(self): await self.player.pause()

    @method()
    async def Play(self): await self.player.play()

    @method()
    async def Seek(self, Offset: "x"):
        if self.player.can_seek: await self.player.seek(self.player.position + Offset / 1_000_000)

    @method()
    async def SetPosition(self, TrackId: "o", Position: "x"):
        current = self.player.current
        if current and TrackId == self._track_id(current["entryId"]) and self.player.can_seek:
            await self.player.seek(Position / 1_000_000)

    @method()
    def OpenUri(self, Uri: "s"): pass

    @signal()
    def Seeked(self, Position: "x") -> "x": return Position

    @staticmethod
    def _track_id(entry_id: str) -> str:
        return "/org/mpris/MediaPlayer2/track/" + entry_id.replace("-", "_")

    @dbus_property(access=PropertyAccess.READ)
    def PlaybackStatus(self) -> "s":
        return {"playing": "Playing", "paused": "Paused"}.get(self.player.state, "Stopped")

    @dbus_property(access=PropertyAccess.READWRITE)
    def LoopStatus(self) -> "s": return {"off": "None", "one": "Track", "all": "Playlist"}[self.player.repeat]

    @LoopStatus.setter
    def LoopStatus(self, value: "s") -> None: self.player.set_repeat({"None": "off", "Track": "one", "Playlist": "all"}.get(value, "off"))

    @dbus_property(access=PropertyAccess.READ)
    def Rate(self) -> "d": return 1.0

    @dbus_property(access=PropertyAccess.READWRITE)
    def Shuffle(self) -> "b": return self.player.shuffle

    @Shuffle.setter
    def Shuffle(self, value: "b") -> None: self.player.set_shuffle(value)

    @dbus_property(access=PropertyAccess.READ)
    def Metadata(self) -> "a{sv}":
        current = self.player.current
        if not current: return {}
        media = current["media"]
        data = {
            "mpris:trackid": Variant("o", self._track_id(current["entryId"])),
            "xesam:title": Variant("s", str(media.get("title") or media.get("videoId") or "OmaTube")),
            "xesam:artist": Variant("as", [str(media.get("author") or "Автор неизвестен")]),
            "xesam:url": Variant("s", str(media.get("canonicalUrl") or "")),
        }
        if media.get("thumbnailUrl"): data["mpris:artUrl"] = Variant("s", str(media["thumbnailUrl"]))
        if self.player.duration is not None: data["mpris:length"] = Variant("x", int(self.player.duration * 1_000_000))
        return data

    @dbus_property(access=PropertyAccess.READWRITE)
    def Volume(self) -> "d": return self.player.volume / 100

    @Volume.setter
    def Volume(self, value: "d") -> None:
        self.player.volume = max(0.0, min(100.0, value * 100))
        self.player.persist()
        asyncio.get_running_loop().create_task(self.player.mpv.set_volume(self.player.volume))

    @dbus_property(access=PropertyAccess.READ)
    def Position(self) -> "x": return int(self.player.position * 1_000_000)

    @dbus_property(access=PropertyAccess.READ)
    def MinimumRate(self) -> "d": return 1.0

    @dbus_property(access=PropertyAccess.READ)
    def MaximumRate(self) -> "d": return 1.0

    @dbus_property(access=PropertyAccess.READ)
    def CanGoNext(self) -> "b": return bool(self.player.queue)

    @dbus_property(access=PropertyAccess.READ)
    def CanGoPrevious(self) -> "b": return bool(self.player.current_id)

    @dbus_property(access=PropertyAccess.READ)
    def CanPlay(self) -> "b": return bool(self.player.queue)

    @dbus_property(access=PropertyAccess.READ)
    def CanPause(self) -> "b": return self.player.state in {"playing", "paused"}

    @dbus_property(access=PropertyAccess.READ)
    def CanSeek(self) -> "b": return self.player.can_seek

    @dbus_property(access=PropertyAccess.READ)
    def CanControl(self) -> "b": return True

    def notify(self) -> None:
        self.emit_properties_changed({
            "PlaybackStatus": self.PlaybackStatus, "Metadata": self.Metadata,
            "Volume": self.Volume, "Shuffle": self.Shuffle, "LoopStatus": self.LoopStatus,
            "CanGoNext": self.CanGoNext, "CanGoPrevious": self.CanGoPrevious,
            "CanPlay": self.CanPlay, "CanPause": self.CanPause, "CanSeek": self.CanSeek,
        })


class MprisBridge:
    def __init__(self, player: Any) -> None:
        self.player = player; self.bus: MessageBus | None = None; self.interface = MprisPlayer(player)

    async def start(self) -> None:
        self.bus = await MessageBus().connect()
        self.bus.export("/org/mpris/MediaPlayer2", MprisRoot())
        self.bus.export("/org/mpris/MediaPlayer2", self.interface)
        await self.bus.request_name("org.mpris.MediaPlayer2.omatube")

    def notify(self) -> None:
        if self.bus: self.interface.notify()

    def stop(self) -> None:
        if self.bus: self.bus.disconnect(); self.bus = None
