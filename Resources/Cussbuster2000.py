#!/usr/bin/env python3
import sys
import re
from pathlib import Path

# List of profane words to check. Extend this list as needed.
PROFANE_WORDS = [
    "ass",
    "bitch",
    "shit",
    "bullshit",
    "fuck",
    "whore",
    "cunt",
    "niger",
    "dick",
    "penis",
    "porn",
    "sex",
    "vagina",
    "damn",
    "hell",
    "bastard",
    "piss",
    "motherfucker",
    "cock",
    "slut",
    "hoe",
    "goddamn",
    "oh my God"
    "God Damn"
    
    
    
    


    
    # add more profane words here
]
MASK_CHAR = '*'


def mask_word(word: str) -> str:
    """Return masked version of the word, preserving the case of the first character."""
    if len(word) <= 1:
        return MASK_CHAR
    first, rest = word[0], word[1:]
    return first + MASK_CHAR * len(rest)


def load_subtitle(sub_path: Path):
    """Parse .srt or .vtt file into a list of entries with start, end, and text."""
    # Support both comma and dot for milliseconds
    pattern = re.compile(r"(\d{2}:\d{2}:\d{2}[,\.]\d{3})\s+-->\s+(\d{2}:\d{2}:\d{2}[,\.]\d{3})")
    raw = sub_path.read_text(encoding='utf-8', errors='ignore')
    entries = []
    blocks = raw.strip().split('\n\n')
    for block in blocks:
        lines = block.strip().splitlines()
        # Skip WebVTT header if present
        if lines and lines[0].startswith('WEBVTT'):
            continue
        # Find timecode line
        time_line = None
        text_lines = []
        for line in lines:
            if not time_line and pattern.match(line):
                time_line = line
            elif time_line:
                text_lines.append(line)
        if not time_line or not text_lines:
            continue
        start, end = pattern.match(time_line).groups()
        text = ' '.join(text_lines)
        entries.append({'start': start, 'end': end, 'text': text})
    return entries


def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} path/to/file.srt|.vtt")
        sys.exit(1)

    sub_file = Path(sys.argv[1])
    if not sub_file.exists() or sub_file.suffix.lower() not in ('.srt', '.vtt'):
        print("Please provide a valid .srt or .vtt subtitle file.")
        sys.exit(1)

    entries = load_subtitle(sub_file)

    profane_pattern = re.compile(r"\b(?:" + "|".join(map(re.escape, PROFANE_WORDS)) + r")\b", flags=re.IGNORECASE)
    report = {}

    for entry in entries:
        for match in profane_pattern.finditer(entry['text']):
            word = match.group(0)
            start_time = entry['start']
            # Get context
            words = entry['text'].split()
            # Find the index of the match in the split words
            try:
                idx = [w.lower() for w in words].index(word.lower())
            except ValueError:
                idx = None
            if idx is not None:
                start_idx = max(0, idx-3)
                end_idx = min(len(words), idx+4)
                context_words = words[start_idx:end_idx]
                # Mask the profane word in context
                context_idx = idx - start_idx
                if 0 <= context_idx < len(context_words):
                    context_words[context_idx] = mask_word(words[idx])
                context = ' '.join(context_words)
            else:
                context = entry['text']
            report.setdefault(word.lower(), []).append((word, start_time, context))
    if not report:
        print("No profane words detected.")
        return
    
    print("PROFANITY DETECTED")
    print(f"Profanity report for: {sub_file.name}")
    for key, occurrences in report.items():
        for word, time, context in occurrences:
            masked = mask_word(word)
            print(f"{masked} at {time} | context: ...{context}...")

if __name__ == '__main__':
    main()
