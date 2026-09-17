# Cloud narration

Use the user's chosen provider. ElevenLabs is one supported route: its speech API returns audio from text, with a selected voice and model.

- API: https://elevenlabs.io/docs/api-reference/text-to-speech/convert
- Model capabilities and limits: https://elevenlabs.io/docs/overview/models
- Manual Studio workflow: https://elevenlabs.io/docs/help-center/product/studio/studio/what-is-studio

Check current limits before implementation; split long chapters at paragraph or sentence boundaries within the chosen model's request limit. Use available continuity parameters when supported. Keep chunk order in a manifest and join audio with ffmpeg after normalizing sample rate and channels. Save the exact input scripts and provider/model/voice identifiers for reproducibility. Retain successful chunks if a later request fails, and avoid automatically repeating billable requests with uncertain outcomes.

Credentials belong in the environment (for example ELEVENLABS_API_KEY), never scripts or generated artifacts. Cloud synthesis sends the narration to the provider and consumes its usage allowance; establish the provider choice if not already authorized, while completing script preparation first. Never silently fall back from local synthesis to an external paid service.

Validate outputs using ffprobe and supply the same chapter audio, combined MP3, duration index, scripts, and coverage report as the local path. Studio supports HTML and text import; convert Markdown to reviewed narration text before import. Browser use is a manual fallback, not required for API automation.
