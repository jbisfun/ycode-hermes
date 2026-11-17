"""ycode-hermes: `hermes ycode-acp`, the ACP adapter with every Hermes session visible.

Stock `hermes acp` lists (session/list) and loads (session/load) only sessions an editor
created over ACP. `hermes ycode-acp` runs the same adapter with those two filters widened,
so CLI, TUI/desktop and gateway chats show up in ycode's threads sidebar and open there.
Subagent, cron and one-shot sessions stay hidden.
"""
import json
import logging

log = logging.getLogger(__name__)

HIDDEN_SOURCES = {"subagent", "cron", "oneshot"}


def _with_cwd(row):
    """Non-ACP rows keep their directory in the `cwd` column; the adapter reads model_config."""
    row = dict(row)
    try:
        meta = json.loads(row.get("model_config") or "{}")
    except (TypeError, ValueError):
        meta = {}
    if not isinstance(meta, dict):
        meta = {}
    if not meta.get("cwd") and row.get("cwd"):
        meta["cwd"] = row["cwd"]
        row["model_config"] = json.dumps(meta)
    return row


def _patch():
    from pathlib import Path

    from acp_adapter import catalog, session
    from hermes_state import SessionDB

    def read_catalog_rows(path):
        path = Path(path)
        if not path.exists():
            return {}
        with SessionDB(db_path=path, read_only=True) as db:
            rows = db.list_sessions_rich(
                exclude_sources=sorted(HIDDEN_SOURCES),
                min_message_count=1,
                order_by_last_active=True,
                limit=1000,
            )
        return {str(row["id"]): _with_cwd(row) for row in rows}

    catalog.read_catalog_rows = read_catalog_rows

    original_restore = session.SessionManager._restore

    def _restore(self, session_id):
        state = original_restore(self, session_id)
        if state is not None:
            return state
        # Not an ACP row: load it through the same path, presented as one.
        db = self._get_db()
        row = db.get_session(session_id) if db is not None else None
        if row is None or row.get("source") in HIDDEN_SOURCES:
            return None
        acp_row = _with_cwd(row)
        acp_row["source"] = "acp"

        class _DB:
            def __getattr__(self, name):
                return getattr(db, name)

            def get_session(self, sid):
                return acp_row if sid == session_id else db.get_session(sid)

        get_db = self._get_db
        self._get_db = lambda: _DB()
        try:
            return original_restore(self, session_id)
        finally:
            self._get_db = get_db

    session.SessionManager._restore = _restore


def _setup(parser):
    parser.add_argument("--check", action="store_true", help="Check the ACP adapter, then exit")


def _run(args):
    from acp_adapter import entry

    _patch()
    entry.main(["--check"] if getattr(args, "check", False) else [])


def register(ctx):
    ctx.register_cli_command(
        name="ycode-acp",
        help="ACP adapter listing every Hermes session (for ycode)",
        setup_fn=_setup,
        handler_fn=_run,
        description="Like `hermes acp`, but session/list and session/load include CLI, "
        "TUI and gateway sessions, not only editor-created ones.",
    )
