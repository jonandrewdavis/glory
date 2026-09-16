#!/usr/bin/env python3
"""Bake the public PlayFlow client credential without booting game autoloads."""
import json
import os
import re
from pathlib import Path

key = os.environ.get("PLAYFLOW_CLIENT_KEY", "")
if not re.fullmatch(r"pfclient_[A-Za-z0-9_-]+", key):
    raise SystemExit("PLAYFLOW_CLIENT_KEY must be a client key (pfclient_...).")
target = Path(__file__).resolve().parent.parent / "networking/playflow_config.tres"
target.write_text(
    '[gd_resource type="Resource" load_steps=2 format=3]\n\n'
    '[ext_resource type="Script" path="res://networking/playflow_config.gd" id="1"]\n\n'
    '[resource]\nscript = ExtResource("1")\n'
    f'client_key = {json.dumps(key)}\n'
)
