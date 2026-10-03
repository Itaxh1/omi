"""Real-path proof: an on-device (custom STT) conversation past the free plan's minutes.

The #7690 gate skips Omi-paid structuring for a free user whose minutes are used up. This
runs the real ``process_conversation`` and the real lifecycle persist against a loopback
Firestore emulator, then reads the stored row back: it must finish as the no-LLM
deterministic minimum (title from the transcript, empty overview, ``processing_state``
``none``), not stay ``processing``.

firebase emulators:exec --only firestore --project demo-transcript-only \
  'PYTHONPATH=backend backend/.venv/bin/pytest -q backend/tests/integration/test_custom_stt_past_limit_emulator.py'
"""

from datetime import datetime, timedelta, timezone
import os
from urllib.parse import urlparse
import uuid

import fakeredis
from google.auth.credentials import AnonymousCredentials
from google.cloud import firestore
import pytest

from database import _client, redis_db
from models.conversation import Conversation
from models.conversation_enums import ConversationProcessingState, ConversationStatus
from testing.hermetic_network import block_outbound_network
from utils.conversations.processing_trigger import ProcessingTrigger
import utils.conversations.process_conversation as process_module

PROJECT = 'demo-transcript-only'
FREE_PLAN_SECONDS = 300 * 60


@pytest.fixture
def store(monkeypatch):
    host = os.environ.get('FIRESTORE_EMULATOR_HOST', '')
    if urlparse(f'//{host}').hostname not in {'localhost', '127.0.0.1', '::1'}:
        pytest.fail('This proof requires a loopback Firestore emulator')
    db = firestore.Client(project=PROJECT, credentials=AnonymousCredentials())
    monkeypatch.setattr(_client, '_firestore_client', db)
    monkeypatch.setattr(redis_db, 'r', fakeredis.FakeRedis(decode_responses=True))
    # Usage only counts against the plan after the subscription launch date.
    monkeypatch.setenv('SUBSCRIPTION_LAUNCH_DATE', '2026-01-01')
    with block_outbound_network():
        yield db


def _seed_free_user_past_limit(db, uid: str, now: datetime) -> None:
    user = db.collection('users').document(uid)
    user.set({'time_zone': 'America/New_York', 'subscription': {'plan': 'basic', 'status': 'active'}})
    hour_id = f'{now.year}-{now.month:02d}-{now.day:02d}-{now.hour:02d}'
    user.collection('hourly_usage').document(hour_id).set(
        {
            'id': hour_id,
            'year': now.year,
            'month': now.month,
            'day': now.day,
            'hour': now.hour,
            # Ten minutes past the free plan's 300.
            'speech_seconds': FREE_PLAN_SECONDS + 600,
            'transcription_seconds': 0,
        }
    )


def _seed_on_device_conversation(db, uid: str, conversation_id: str, now: datetime) -> dict:
    started = now - timedelta(minutes=23)
    row = {
        'id': conversation_id,
        'created_at': started,
        'started_at': started,
        'finished_at': now,
        'language': 'en',
        'source': 'phone',
        'status': ConversationStatus.processing.value,
        'uses_custom_stt': True,
        'structured': {'title': '', 'overview': '', 'emoji': '', 'category': 'other'},
        'transcript_segments': [
            {
                'id': 's1',
                'text': 'Is the demo still on Thursday?',
                'speaker': 'SPEAKER_00',
                'speaker_id': 0,
                'is_user': False,
                'start': 0.0,
                'end': 2.0,
            },
            {
                'id': 's2',
                'text': 'Thursday at ten. I want to open with the Instagram numbers.',
                'speaker': 'SPEAKER_00',
                'speaker_id': 0,
                'is_user': False,
                'start': 9.0,
                'end': 13.0,
            },
        ],
    }
    db.collection('users').document(uid).collection('conversations').document(conversation_id).set(row)
    return row


def test_custom_stt_conversation_past_free_minutes_finishes_without_a_summary(store, monkeypatch):
    uid = uuid.uuid4().hex
    conversation_id = uuid.uuid4().hex
    now = datetime.now(timezone.utc)
    _seed_free_user_past_limit(store, uid, now)
    row = _seed_on_device_conversation(store, uid, conversation_id, now)

    def no_llm(*args, **kwargs):
        raise AssertionError('no model call may run for a free user past the limit')

    monkeypatch.setattr(process_module, 'get_transcript_structure', no_llm)

    process_module.process_conversation(
        uid, 'en', Conversation(**row), trigger=ProcessingTrigger.CAPTURE_END, defer_derived_effects=True
    )

    stored = store.collection('users').document(uid).collection('conversations').document(conversation_id).get()
    data = stored.to_dict()
    assert data['status'] == ConversationStatus.completed.value, 'the row must not stay processing'
    assert data.get('is_locked', False) is False
    assert data.get('processing_state') == ConversationProcessingState.none.value
    assert data['structured']['title'] == 'Is the demo still on Thursday?'
    assert data['structured']['overview'] == ''
    assert data['structured'].get('action_items', []) == []
