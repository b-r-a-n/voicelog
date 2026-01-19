import os
from datetime import datetime, timedelta, timezone
from io import BytesIO
from pathlib import Path
from typing import Optional
import uuid

from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import inch
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer

EXPORT_PATH = os.environ.get("EXPORT_PATH", "./data/exports")
EXPORT_EXPIRY_HOURS = int(os.environ.get("EXPORT_EXPIRY_HOURS", "24"))


class ExportService:
    def __init__(self, export_path: str = EXPORT_PATH):
        self.export_path = Path(export_path)
        self.export_path.mkdir(parents=True, exist_ok=True)

    def generate_export_id(self) -> str:
        return str(uuid.uuid4())

    def get_expiry_time(self) -> datetime:
        return datetime.now(timezone.utc) + timedelta(hours=EXPORT_EXPIRY_HOURS)

    def export_to_markdown(
        self,
        title: str,
        transcript: str,
        summary: Optional[str] = None,
        recorded_at: Optional[datetime] = None,
        tags: Optional[list[str]] = None,
    ) -> tuple[str, str]:
        """
        Export note to Markdown format.

        Returns:
            Tuple of (export_id, file_path)
        """
        export_id = self.generate_export_id()
        file_path = self.export_path / f"{export_id}.md"

        lines = [f"# {title}", ""]

        if recorded_at:
            lines.append(f"**Recorded:** {recorded_at.strftime('%Y-%m-%d %H:%M')}")
            lines.append("")

        if tags:
            lines.append(f"**Tags:** {', '.join(tags)}")
            lines.append("")

        if summary:
            lines.append("## Summary")
            lines.append("")
            lines.append(summary)
            lines.append("")

        lines.append("## Transcript")
        lines.append("")
        lines.append(transcript)

        content = "\n".join(lines)
        file_path.write_text(content, encoding="utf-8")

        return export_id, str(file_path)

    def export_to_pdf(
        self,
        title: str,
        transcript: str,
        summary: Optional[str] = None,
        recorded_at: Optional[datetime] = None,
        tags: Optional[list[str]] = None,
    ) -> tuple[str, str]:
        """
        Export note to PDF format.

        Returns:
            Tuple of (export_id, file_path)
        """
        export_id = self.generate_export_id()
        file_path = self.export_path / f"{export_id}.pdf"

        doc = SimpleDocTemplate(
            str(file_path),
            pagesize=letter,
            rightMargin=inch,
            leftMargin=inch,
            topMargin=inch,
            bottomMargin=inch,
        )

        styles = getSampleStyleSheet()
        title_style = styles["Heading1"]
        heading_style = styles["Heading2"]
        body_style = ParagraphStyle(
            "Body",
            parent=styles["Normal"],
            spaceBefore=6,
            spaceAfter=6,
            leading=14,
        )
        meta_style = ParagraphStyle(
            "Meta",
            parent=styles["Normal"],
            fontSize=10,
            textColor="gray",
        )

        story = []

        # Title
        story.append(Paragraph(title, title_style))
        story.append(Spacer(1, 12))

        # Metadata
        if recorded_at:
            story.append(Paragraph(
                f"<b>Recorded:</b> {recorded_at.strftime('%Y-%m-%d %H:%M')}",
                meta_style
            ))

        if tags:
            story.append(Paragraph(
                f"<b>Tags:</b> {', '.join(tags)}",
                meta_style
            ))

        story.append(Spacer(1, 24))

        # Summary
        if summary:
            story.append(Paragraph("Summary", heading_style))
            story.append(Spacer(1, 6))
            for para in summary.split("\n\n"):
                if para.strip():
                    story.append(Paragraph(para, body_style))
            story.append(Spacer(1, 24))

        # Transcript
        story.append(Paragraph("Transcript", heading_style))
        story.append(Spacer(1, 6))
        for para in transcript.split("\n\n"):
            if para.strip():
                # Escape special XML characters
                safe_para = para.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
                story.append(Paragraph(safe_para, body_style))

        doc.build(story)

        return export_id, str(file_path)

    def get_export_path(self, export_id: str, format: str) -> Optional[Path]:
        """Get the file path for an export if it exists."""
        extension = "pdf" if format == "pdf" else "md"
        file_path = self.export_path / f"{export_id}.{extension}"
        return file_path if file_path.exists() else None

    def cleanup_expired_exports(self) -> int:
        """Remove expired export files. Returns count of deleted files."""
        now = datetime.now(timezone.utc)
        deleted = 0

        for file_path in self.export_path.iterdir():
            if file_path.is_file():
                mtime = datetime.fromtimestamp(file_path.stat().st_mtime, tz=timezone.utc)
                if now - mtime > timedelta(hours=EXPORT_EXPIRY_HOURS):
                    file_path.unlink()
                    deleted += 1

        return deleted


# Singleton instance
export_service = ExportService()
