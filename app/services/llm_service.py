import os
from abc import ABC, abstractmethod
from typing import Optional

# LLM Provider configuration
LLM_PROVIDER = os.environ.get("LLM_PROVIDER", "anthropic")  # anthropic, openai, ollama, or groq
ANTHROPIC_API_KEY = os.environ.get("ANTHROPIC_API_KEY")
OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY")
OLLAMA_BASE_URL = os.environ.get("OLLAMA_BASE_URL", "http://localhost:11434")
OLLAMA_MODEL = os.environ.get("OLLAMA_MODEL", "llama3.2")
GROQ_API_KEY = os.environ.get("GROQ_API_KEY")
GROQ_MODEL = os.environ.get("GROQ_MODEL", "llama-3.3-70b-versatile")

DEFAULT_SUMMARY_PROMPT = """Please provide a concise summary of the following voice dictation transcript.
Focus on the main topics, key points, and any action items mentioned.
Keep the summary to 2-3 paragraphs maximum.

Transcript:
{transcript}

Summary:"""


class LLMProvider(ABC):
    @abstractmethod
    async def summarize(self, transcript: str, custom_prompt: Optional[str] = None) -> str:
        pass


class AnthropicProvider(LLMProvider):
    def __init__(self):
        if not ANTHROPIC_API_KEY:
            raise ValueError("ANTHROPIC_API_KEY environment variable is required")
        import anthropic
        self.client = anthropic.Anthropic(api_key=ANTHROPIC_API_KEY)

    async def summarize(self, transcript: str, custom_prompt: Optional[str] = None) -> str:
        prompt = custom_prompt or DEFAULT_SUMMARY_PROMPT
        prompt = prompt.replace("{transcript}", transcript)

        message = self.client.messages.create(
            model="claude-sonnet-4-20250514",
            max_tokens=1024,
            messages=[
                {"role": "user", "content": prompt}
            ]
        )
        return message.content[0].text


class OpenAIProvider(LLMProvider):
    def __init__(self):
        if not OPENAI_API_KEY:
            raise ValueError("OPENAI_API_KEY environment variable is required")
        from openai import OpenAI
        self.client = OpenAI(api_key=OPENAI_API_KEY)

    async def summarize(self, transcript: str, custom_prompt: Optional[str] = None) -> str:
        prompt = custom_prompt or DEFAULT_SUMMARY_PROMPT
        prompt = prompt.replace("{transcript}", transcript)

        response = self.client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "user", "content": prompt}
            ],
            max_tokens=1024,
        )
        return response.choices[0].message.content


class OllamaProvider(LLMProvider):
    def __init__(self):
        import httpx
        self.base_url = OLLAMA_BASE_URL
        self.model = OLLAMA_MODEL
        self.client = httpx.AsyncClient(timeout=120.0)

    async def summarize(self, transcript: str, custom_prompt: Optional[str] = None) -> str:
        prompt = custom_prompt or DEFAULT_SUMMARY_PROMPT
        prompt = prompt.replace("{transcript}", transcript)

        response = await self.client.post(
            f"{self.base_url}/api/generate",
            json={
                "model": self.model,
                "prompt": prompt,
                "stream": False,
            }
        )
        response.raise_for_status()
        return response.json()["response"]


class GroqProvider(LLMProvider):
    def __init__(self):
        if not GROQ_API_KEY:
            raise ValueError("GROQ_API_KEY environment variable is required")
        from openai import OpenAI
        self.client = OpenAI(
            api_key=GROQ_API_KEY,
            base_url="https://api.groq.com/openai/v1"
        )
        self.model = GROQ_MODEL

    async def summarize(self, transcript: str, custom_prompt: Optional[str] = None) -> str:
        prompt = custom_prompt or DEFAULT_SUMMARY_PROMPT
        prompt = prompt.replace("{transcript}", transcript)

        response = self.client.chat.completions.create(
            model=self.model,
            messages=[
                {"role": "user", "content": prompt}
            ],
            max_tokens=1024,
        )
        return response.choices[0].message.content


class LLMService:
    def __init__(self):
        self._provider: Optional[LLMProvider] = None

    @property
    def provider(self) -> LLMProvider:
        if self._provider is None:
            self._provider = self._create_provider()
        return self._provider

    def _create_provider(self) -> LLMProvider:
        if LLM_PROVIDER == "anthropic":
            return AnthropicProvider()
        elif LLM_PROVIDER == "openai":
            return OpenAIProvider()
        elif LLM_PROVIDER == "ollama":
            return OllamaProvider()
        elif LLM_PROVIDER == "groq":
            return GroqProvider()
        else:
            raise ValueError(f"Unknown LLM provider: {LLM_PROVIDER}")

    async def summarize(self, transcript: str, custom_prompt: Optional[str] = None) -> str:
        return await self.provider.summarize(transcript, custom_prompt)


# Singleton instance
llm_service = LLMService()
