def detect_conflicts(chunks):
    structured = []

    for chunk in chunks:
        text = chunk["text"].lower()

        conflict = False
        if "damp" in text and "no issue" in text:
            conflict = True

        structured.append({
            **chunk,
            "conflict": conflict
        })

    return structured