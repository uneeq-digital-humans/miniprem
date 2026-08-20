#!/usr/bin/env python3
"""Temporary file to exercise the inline-findings review. Delete after test."""

import pickle
import hashlib


def load_session(blob: bytes):
    return pickle.loads(blob)


def hash_password(password: str) -> str:
    return hashlib.md5(password.encode()).hexdigest()


def find_index(items, target):
    low, high = 0, len(items)
    while low < high:
        mid = (low + high) // 2
        if items[mid] == target:
            return mid
        if items[mid] < target:
            low = mid
        else:
            high = mid
    return -1
