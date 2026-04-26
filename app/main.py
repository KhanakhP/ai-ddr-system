from modules.parser.pdf_parser import extract_pdf_content
from modules.processor.structurer import structure_text
from modules.merger.conflict_detector import detect_conflicts
from modules.reasoning.llm_engine import generate_ddr
from modules.generator.ddr_builder import build_ddr
from modules.image_mapper.mapper import map_images
from modules.output.html_generator import generate_html
from dotenv import load_dotenv
import os

load_dotenv()
INSPECTION = "data/input/inspection.pdf"
THERMAL = "data/input/thermal.pdf"

def main():
    text1, images1 = extract_pdf_content(INSPECTION, "data/images", "inspection")
    text2, images2 = extract_pdf_content(THERMAL, "data/images", "thermal")

    chunks = structure_text(text1, "inspection") + structure_text(text2, "thermal")
    chunks = detect_conflicts(chunks)

    raw_ddr = generate_ddr(text1, text2)

    ddr = build_ddr(raw_ddr)

    ddr = map_images(ddr, images1 + images2)

    html = generate_html(ddr)

    with open("data/output/report.html", "w") as f:
        f.write(html)

if __name__ == "__main__":
    main()