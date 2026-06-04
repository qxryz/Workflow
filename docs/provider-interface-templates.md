# Provider Interface Templates

Provider interface templates are resettable registration starting points. They are separate from the legacy endpoint preset registry, which remains available only for decoding and migration.

`verified` means the official documentation clearly identifies the route role. It does not promise that every model accepts every optional field. `needs_review` means the route or request shape still needs confirmation against the selected model's official documentation before the registration is promoted.

The registry records `checkedAt = 2026-06-04` and a template version. Resetting an interface reconstructs the current system template without deleting the discovered model or provider credentials. Conversation templates compile text and media references into separate Messages content blocks so an attachment cannot overwrite the current prompt. Provider-specific media blocks remain editable in the registration wizard.

| Template | Provider | Mode | Official docs | Status | Notes |
| --- | --- | --- | --- | --- | --- |
| `agnes.chat` | Agnes AI | sync | [Agnes 2.0 Flash](https://agnes-ai.com/doc/agnes-20-flash) | verified | OpenAI-compatible `agnes-2.0-flash`; exposes temperature, top_p, max_tokens, stream, tools, tool_choice, thinking, and chat_template_kwargs controls |
| `agnes.chat.streaming` | Agnes AI | SSE | [Agnes 2.0 Flash](https://agnes-ai.com/doc/agnes-20-flash) | verified | Streaming `agnes-2.0-flash` template with `stream: true` and delta output parsing |
| `agnes.image.21` | Agnes AI | sync | [Agnes Image 2.1 Flash](https://agnes-ai.com/doc/agnes-image-21-flash) | verified | Most advanced image model; text-to-image and image-to-image through `extra_body.image` |
| `agnes.image.20` | Agnes AI | sync | [Agnes Image 2.0 Flash](https://agnes-ai.com/doc/agnes-image-20-flash) | verified | Image-to-image/editing starter with `tags`, `seed`, multi-image `extra_body.image`, and URL responses |
| `agnes.video` | Agnes AI | async | [Agnes Video V2.0](https://agnes-ai.com/doc/agnes-video-v20) | verified | Asynchronous `/videos` task with `/videos/{task_id}` polling, frame/FPS controls, image-to-video, and keyframe fields |
| `openai.responses` | OpenAI | sync | [Responses API](https://platform.openai.com/docs/api-reference/responses) | verified | General response generation |
| `openai.chat` | OpenAI | sync | [Chat Completions API](https://platform.openai.com/docs/api-reference/chat/create) | verified | Conversation messages |
| `openai.images` | OpenAI | sync | [Images API](https://platform.openai.com/docs/api-reference/images) | verified | Image generation starter |
| `openai.videos` | OpenAI | async | [Videos API](https://platform.openai.com/docs/api-reference/videos/content) | verified | Multipart create and `/videos/{task_id}` polling |
| `openai.audio.speech` | OpenAI | sync | [Audio API](https://platform.openai.com/docs/api-reference/audio) | verified | Binary speech response |
| `openai.audio.transcriptions` | OpenAI | sync | [Audio API](https://platform.openai.com/docs/api-reference/audio) | verified | Multipart audio upload |
| `openai.embeddings` | OpenAI | sync | [Embeddings API](https://platform.openai.com/docs/api-reference/embeddings/create) | verified | Text embeddings |
| `volc.chat` | Volcengine Ark | sync | [Ark Chat API](https://www.volcengine.com/docs/82379/1302009) | verified | Text and supported media travel through Messages content blocks |
| `volc.seedream.image` | Volcengine Ark | sync | [Seedream image generation](https://www.volcengine.com/docs/82379/1541523) | needs_review | Confirm selected Seedream model fields |
| `volc.seedance.audiovideo` | Volcengine Ark | async | [Seedance task API](https://www.volcengine.com/docs/82379/1520757) | needs_review | Confirm selected Seedance audio-video fields |
| `volc.seed3d` | Volcengine Ark | async | [Seed3D task API](https://www.volcengine.com/docs/82379/1856293) | needs_review | Confirm selected Seed3D output asset path |
| `aliyun.compatible.chat` | Aliyun Bailian | sync | [Qwen API reference](https://help.aliyun.com/zh/model-studio/use-qwen-by-calling-api) | verified | OpenAI-compatible chat route |
| `aliyun.multimodal` | Aliyun Bailian | sync | [DashScope API details](https://help.aliyun.com/zh/dashscope/developer-reference/api-details) | needs_review | Native multimodal starter |
| `aliyun.qwen.omni` | Aliyun Bailian | SSE | [Qwen Omni](https://help.aliyun.com/zh/model-studio/user-guide/qwen-omni) | verified | Streaming is required |
| `aliyun.qwen.image` | Aliyun Bailian | sync | [Qwen Image API](https://help.aliyun.com/zh/model-studio/qwen-image-api) | verified | Extracts generated URLs from `output.choices[].message.content[].image` |
| `aliyun.wan.image` | Aliyun Bailian | async | [Wan text-to-image API](https://help.aliyun.com/zh/model-studio/text-to-image-api-reference) | needs_review | Injects `X-DashScope-Async: enable` |
| `aliyun.wan.video` | Aliyun Bailian | async | [Wan text-to-video API](https://help.aliyun.com/zh/model-studio/text-to-video-api-reference) | verified | Injects `X-DashScope-Async: enable`; registers Wan 2.7 common controls |
| `aliyun.tts` | Aliyun Bailian | sync | [Text to speech](https://help.aliyun.com/zh/model-studio/text-to-speech) | needs_review | Confirm voice and format fields for the selected model |
| `aliyun.asr` | Aliyun Bailian | sync | [Speech to text](https://help.aliyun.com/zh/model-studio/speech-to-text) | needs_review | Confirm sync versus task flow for the selected model |
| `aliyun.embeddings` | Aliyun Bailian | sync | [Embeddings and rerank](https://help.aliyun.com/zh/model-studio/embedding-and-rerank/) | needs_review | Text embedding starter |
| `aliyun.rerank` | Aliyun Bailian | sync | [Text rerank API](https://help.aliyun.com/zh/model-studio/text-rerank-api) | needs_review | Confirm native versus compatible rerank route |
| `deepseek.chat` | DeepSeek | sync | [Chat completion](https://api-docs.deepseek.com/api/create-chat-completion) | verified | Conversation messages |
| `deepseek.reasoning` | DeepSeek | sync | [Chat completion](https://api-docs.deepseek.com/api/create-chat-completion) | verified | Starts with thinking enabled |
| `minimax.chat` | MiniMax China | sync | [OpenAI SDK](https://platform.minimaxi.com/docs/api-reference/text-openai-api) | verified | Current OpenAI-compatible Chat Completions route |
| `minimax.chat.multimodal` | MiniMax China | sync | [OpenAI SDK](https://platform.minimaxi.com/docs/api-reference/text-openai-api) | verified | MiniMax-M3 text, image, and video understanding through Chat Completions |
| `minimax.image` | MiniMax China | sync | [Image generation](https://platform.minimaxi.com/docs/api-reference/image-generation) | verified | Text and subject-reference image generation |
| `minimax.video` | MiniMax China | async | [Video generation](https://platform.minimaxi.com/docs/api-reference/video-generation-t2v) | verified | Polls `/query/video_generation?task_id={task_id}` |
| `minimax.tts` | MiniMax China | sync | [Synchronous speech](https://platform.minimaxi.com/docs/api-reference/speech-t2a-http) | verified | Voice, format, and speed controls |
| `minimax.music` | MiniMax China | sync | [Music generation](https://platform.minimaxi.com/docs/api-reference/music-generation) | verified | Prompt and optional reference audio |
| `custom.chat` | Custom OpenAI-compatible | sync | [OpenAI Chat Completions reference](https://platform.openai.com/docs/api-reference/chat/create) | needs_review | Confirm compatibility against the custom provider |
| `custom.special.sync` | Custom OpenAI-compatible | sync | [OpenAI API introduction](https://platform.openai.com/docs/api-reference/introduction) | needs_review | Empty special-interface starter |
| `custom.special.sse` | Custom OpenAI-compatible | SSE | [OpenAI API introduction](https://platform.openai.com/docs/api-reference/introduction) | needs_review | Empty streaming special-interface starter |
| `custom.special.websocket` | Custom OpenAI-compatible | WebSocket | [OpenAI API introduction](https://platform.openai.com/docs/api-reference/introduction) | needs_review | Empty WebSocket special-interface starter |
