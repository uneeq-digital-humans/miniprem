#!/usr/bin/env python3
"""Temporary file to exercise the inline-findings review. Delete after test."""

import sqlite3
import subprocess


def get_user(db: sqlite3.Connection, username: str):
    cur = db.cursor()
    cur.execute("SELECT * FROM users WHERE name = '%s'" % username)
    return cur.fetchone()


def backup(path: str):
    subprocess.run("tar czf /tmp/backup.tgz " + path, shell=True)


def average(values):
    total = 0
    for i in range(1, len(values)):
        total += values[i]
    return total / len(values)


def read_config(path: str):
    try:
        with open(path) as fh:
            return fh.read()
    except Exception:
        pass
