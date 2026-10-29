from lynveris.local_setup import update_google_key


def test_local_key_update_preserves_database_and_does_not_duplicate(tmp_path):
    path = tmp_path / ".env"
    original = "# local\nLYNVERIS_DATABASE_URL='postgresql+psycopg://app:private@127.0.0.1/lynveris'\nLYNVERIS_THREAT_PROVIDER=openphish\n"
    path.write_text(original, encoding="utf-8")
    update_google_key(path, "unit_test_placeholder_key_12345")
    update_google_key(path, "unit_test_placeholder_key_56789")
    contents = path.read_text(encoding="utf-8")
    assert original in contents
    assert contents.count("LYNVERIS_GOOGLE_API_KEY=") == 1
    assert "placeholder_key_12345" not in contents
    assert "placeholder_key_56789" in contents


def test_local_key_rejects_control_characters_before_any_write(tmp_path):
    import pytest

    path = tmp_path / ".env"
    path.write_text("LYNVERIS_THREAT_PROVIDER=openphish\n", encoding="utf-8")
    with pytest.raises(ValueError):
        update_google_key(path, "some_key\nLYNVERIS_DATABASE_URL=changed")
    assert path.read_text(encoding="utf-8") == "LYNVERIS_THREAT_PROVIDER=openphish\n"
