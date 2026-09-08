# AI Assistant — pluggable LLM providers

Default provider is **Ollama** on the host. Switch without code changes via env.

| Provider | `LLM_PROVIDER` | Required env |
|----------|----------------|--------------|
| Ollama (local) | `ollama` | `LLM_MODEL` / `OLLAMA_MODEL`, optional `LLM_BASE_URL` |
| OpenAI | `openai` | `OPENAI_API_KEY` or `LLM_API_KEY`, `LLM_MODEL` |
| Anthropic | `anthropic` | `ANTHROPIC_API_KEY` or `LLM_API_KEY`, `LLM_MODEL` |
| Azure OpenAI | `azure` | `AZURE_API_KEY`, `AZURE_API_BASE` / `LLM_BASE_URL`, `LLM_MODEL` (deployment), optional `LLM_API_VERSION` |
| Groq | `groq` | `GROQ_API_KEY` or `LLM_API_KEY`, `LLM_MODEL` |
| OpenAI-compatible | `compatible` | `LLM_BASE_URL`, `LLM_MODEL`, optional `LLM_API_KEY` |

Backed by [LiteLLM](https://github.com/BerriAI/litellm). Agent code depends only on `LLMProvider.complete()`.
