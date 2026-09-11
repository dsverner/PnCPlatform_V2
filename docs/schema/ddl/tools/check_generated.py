"""Fails (exit 1) if any generated view/procedure file differs from a fresh generation."""
import subprocess, sys, os
HERE = os.path.dirname(os.path.abspath(__file__))
sys.exit(subprocess.call([sys.executable, os.path.join(HERE, "generate.py"), "--check", *sys.argv[1:]]))
