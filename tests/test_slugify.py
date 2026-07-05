import pytest

from src.slugify import slugify


def test_basic():
    assert slugify("Hello, World!") == "hello-world"


def test_unicode_normalization():
    assert slugify("Déjà Vu — Again") == "deja-vu-again"


def test_collapses_separators():
    assert slugify("a  b__c--d") == "a-b-c-d"


def test_strips_edge_hyphens():
    assert slugify("  --hello--  ") == "hello"


def test_truncates_on_word_boundary():
    assert slugify("alpha beta gamma", max_length=10) == "alpha-beta"


def test_truncation_never_exceeds_max_length():
    result = slugify("alpha beta gamma", max_length=7)
    assert len(result) <= 7
    assert result == "alpha"


def test_rejects_invalid_max_length():
    with pytest.raises(ValueError):
        slugify("hello", max_length=0)


def test_empty_input():
    assert slugify("") == ""
