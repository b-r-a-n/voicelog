import hashlib
import os
from pathlib import Path
from typing import Optional, Tuple

TRANSCRIPT_SIZE_THRESHOLD = 50 * 1024  # 50KB - store in file if >= this size
STORAGE_PATH = os.environ.get("STORAGE_PATH", "./data/transcripts")


class StorageService:
    def __init__(self, storage_path: str = STORAGE_PATH):
        self.storage_path = Path(storage_path)
        self.storage_path.mkdir(parents=True, exist_ok=True)

    def compute_checksum(self, content: str) -> str:
        """Compute SHA256 checksum for transcript content."""
        return hashlib.sha256(content.encode("utf-8")).hexdigest()

    def store_transcript(
        self,
        user_id: int,
        note_id: int,
        content: str,
    ) -> Tuple[Optional[str], Optional[str], str, int]:
        """
        Store transcript content using hybrid strategy.

        Returns:
            Tuple of (transcript_inline, transcript_path, preview, size)
        """
        size = len(content.encode("utf-8"))
        preview = content[:500] if content else None

        if size < TRANSCRIPT_SIZE_THRESHOLD:
            # Store inline in database
            return content, None, preview, size
        else:
            # Store in file system
            user_dir = self.storage_path / str(user_id)
            user_dir.mkdir(exist_ok=True)

            file_path = user_dir / f"{note_id}.txt"
            file_path.write_text(content, encoding="utf-8")

            return None, str(file_path), preview, size

    def get_transcript(
        self,
        transcript_inline: Optional[str],
        transcript_path: Optional[str],
    ) -> Optional[str]:
        """
        Retrieve transcript content from either inline storage or file.
        """
        if transcript_inline is not None:
            return transcript_inline

        if transcript_path is not None:
            path = Path(transcript_path)
            if path.exists():
                return path.read_text(encoding="utf-8")

        return None

    def delete_transcript_file(self, transcript_path: Optional[str]) -> bool:
        """Delete transcript file if it exists."""
        if transcript_path is None:
            return True

        path = Path(transcript_path)
        if path.exists():
            path.unlink()
            return True
        return False

    def update_transcript(
        self,
        user_id: int,
        note_id: int,
        content: str,
        old_transcript_path: Optional[str],
    ) -> Tuple[Optional[str], Optional[str], str, int]:
        """
        Update transcript content, migrating between inline/file as needed.
        """
        # Delete old file if it existed
        self.delete_transcript_file(old_transcript_path)

        # Store new content using hybrid strategy
        return self.store_transcript(user_id, note_id, content)


# Singleton instance
storage_service = StorageService()
