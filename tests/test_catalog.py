from app.catalog import BY_ID, LAUNCHES


def test_catalog_size():
    assert len(LAUNCHES) == 5


def test_by_id_index_matches_list():
    assert set(BY_ID) == {launch.id for launch in LAUNCHES}


def test_lc101_is_go():
    assert BY_ID["LC-101"].status == "go"


def test_lc102_is_nogo():
    assert BY_ID["LC-102"].status == "no-go"


def test_windows_positive():
    assert all(launch.window_seconds > 0 for launch in LAUNCHES)


def test_unique_pads_or_ids():
    assert len({launch.id for launch in LAUNCHES}) == len(LAUNCHES)
