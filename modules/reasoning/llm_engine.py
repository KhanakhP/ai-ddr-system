from langchain_google_genai import ChatGoogleGenerativeAI
import os
from dotenv import load_dotenv
load_dotenv()
CHAT_MODEL = "gemini-2.5-flash"
llm = ChatGoogleGenerativeAI(model=CHAT_MODEL, temperature=0.2, max_tokens=18000, api_key=os.getenv("GOOGLE_API_KEY"))

def generate_ddr(inspection_text, thermal_text):
    prompt = f"""
Return ONLY valid JSON. No explanation. No markdown.

STRICT FORMAT (MUST FOLLOW EXACTLY):

{{
  "property_issue_summary": "string",
  "area_wise_observations": [
    {{
      "area": "string",
      "inspection_observations": ["string"],
      "thermal_findings": ["string"],
      "combined_finding": "string",
      "images": []
    }}
  ],
  "probable_root_cause": ["string"],
  "severity_assessment": {{
    "level": "Low | Moderate | High | Critical | Unknown",
    "reasoning": "string"
  }},
  "recommended_actions": ["string"],
  "additional_notes": ["string"]
}}

IMPORTANT RULES:
- DO NOT use "observations"
- MUST include ALL fields
- If data missing → use "Not Available" or []
- Do NOT skip fields
- Do NOT rename keys

Inspection:
{inspection_text[:6000]}

Thermal:
{thermal_text[:6000]}
"""

    for _ in range(3):
        response = llm.invoke(prompt)

        print("\n===== GEMINI OUTPUT =====\n")
        print(response.content)
        print("\n=========================\n")

        # check JSON completeness
        if response.content.count("{") == response.content.count("}"):
            return response.content

        print("Retrying due to incomplete JSON...\n")

    raise ValueError("LLM failed to return valid JSON")