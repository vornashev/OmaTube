import unittest

from backend.i18n import resolve, system_language, text
from backend.main import CHOICE_PREFERENCES, DEFAULT_PREFERENCES


class I18nTests(unittest.TestCase):
    def test_system_language_follows_first_supported_variable(self):
        self.assertEqual(system_language({"LANG": "ru_RU.UTF-8"}), "ru")
        self.assertEqual(system_language({"LC_ALL": "en_US.UTF-8", "LANG": "ru_RU.UTF-8"}), "en")
        self.assertEqual(system_language({"LANGUAGE": "de:ru"}), "ru")

    def test_unsupported_or_missing_system_language_falls_back_to_english(self):
        self.assertEqual(system_language({"LANG": "de_DE.UTF-8"}), "en")
        self.assertEqual(system_language({"LANG": "C"}), "en")
        self.assertEqual(system_language({}), "en")

    def test_explicit_preference_wins_over_environment(self):
        self.assertEqual(resolve("ru", {"LANG": "en_US.UTF-8"}), "ru")
        self.assertEqual(resolve("en", {"LANG": "ru_RU.UTF-8"}), "en")
        self.assertEqual(resolve("auto", {"LANG": "ru_RU.UTF-8"}), "ru")
        self.assertEqual(resolve("fr", {"LANG": "de_DE"}), "en")

    def test_text_uses_resolved_language(self):
        self.assertEqual(text("unknown_author", "en"), "Unknown author")
        self.assertEqual(text("unknown_author", "ru"), "Автор неизвестен")

    def test_language_preference_is_auto_by_default_and_validated(self):
        self.assertEqual(DEFAULT_PREFERENCES["language"], "auto")
        self.assertEqual(CHOICE_PREFERENCES["language"], {"auto", "en", "ru"})


if __name__ == "__main__":
    unittest.main()
