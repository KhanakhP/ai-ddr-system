import fitz  # PyMuPDF
import os

def extract_pdf_content(pdf_path, image_dir, prefix):
    doc = fitz.open(pdf_path)
    text = ""
    images = []

    os.makedirs(image_dir, exist_ok=True)

    for page_num, page in enumerate(doc):
        text += page.get_text()

        for img_index, img in enumerate(page.get_images(full=True)):
            xref = img[0]
            base_image = doc.extract_image(xref)
            img_bytes = base_image["image"]

            file_name = f"{prefix}_{page_num}_{img_index}.png"
            file_path = os.path.join(image_dir, file_name)

            with open(file_path, "wb") as f:
                f.write(img_bytes)

            images.append({
                "file": file_path,
                "page": page_num,
                "source": prefix
            })

    return text, images