"""Small LRU caches with both byte budgets and absolute expiry."""
from collections import OrderedDict
import time


class ByteTTLCache:
    def __init__(self, max_bytes: int, max_entries: int, ttl: float, clock=time.monotonic) -> None:
        self.max_bytes = max_bytes
        self.max_entries = max_entries
        self.ttl = ttl
        self.clock = clock
        self.bytes = 0
        self._items = OrderedDict()

    def __len__(self):
        return len(self._items)

    def _remove(self, key):
        entry = self._items.pop(key, None)
        if entry is not None:
            self.bytes -= entry[2]

    def prune(self):
        now = self.clock()
        for key, (_, expires, _) in list(self._items.items()):
            if expires <= now:
                self._remove(key)

    def get(self, key, default=None):
        entry = self._items.get(key)
        if entry is None:
            return default
        value, expires, _ = entry
        if expires <= self.clock():
            self._remove(key)
            return default
        self._items.move_to_end(key)
        return value

    def put(self, key, value, size: int):
        self.prune()
        self._remove(key)
        if size < 0 or size > self.max_bytes:
            return
        self._items[key] = (value, self.clock() + self.ttl, size)
        self.bytes += size
        while self.bytes > self.max_bytes or len(self._items) > self.max_entries:
            self._remove(next(iter(self._items)))
