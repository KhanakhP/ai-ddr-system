def structure_text(text, source):
    chunks = []

    for line in text.split("\n"):
        line = line.strip()

        if len(line) < 10:
            continue

        chunks.append({
            "text": line,
            "source": source
        })

    return chunks