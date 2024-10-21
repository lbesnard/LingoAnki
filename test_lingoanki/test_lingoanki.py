import unittest

from lingoanki.__main__ import generate_unique_id


class TestGenerateUniqueId(unittest.TestCase):
    def test_generate_unique_id_default_length(self):
        # Arrange
        input_string = "test_string"
        expected_length = 9

        # Act
        result = generate_unique_id(input_string)

        # Assert
        self.assertEqual(len(str(result)), expected_length)
        self.assertTrue(isinstance(result, int))
        self.assertEqual(result, 723598865)


if __name__ == "__main__":
    unittest.main()
