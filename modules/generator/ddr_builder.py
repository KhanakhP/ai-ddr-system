import json
import re
from modules.generator.schema import DDR

def extract_json(text):
    match = re.search(r"\{.*\}", text, re.DOTALL)

    if not match:
        raise ValueError("No JSON found")

    json_str = match.group()

    # 🔥 Check if JSON is complete
    if json_str.count("{") != json_str.count("}"):
        raise ValueError("Incomplete JSON from LLM")
    
    return json.loads(json_str)

def fix_schema(data):
    for obs in data.get("area_wise_observations", []):
        # Fix missing fields
        obs["inspection_observations"] = obs.get("inspection_observations", obs.get("observations", []))
        obs["thermal_findings"] = obs.get("thermal_findings", [])
        obs["combined_finding"] = obs.get("combined_finding", "Not Available")
        obs["images"] = obs.get("images", [])

        # Remove wrong key
        if "observations" in obs:
            del obs["observations"]

    return data

def build_ddr(raw_output):
    try:
        data = extract_json(raw_output)
        data = fix_schema(data)
        return DDR(**data)
    except Exception as e:
        print("\n===== RAW LLM OUTPUT =====\n")
        print(raw_output)
        print("\n=========================\n")
        raise ValueError("Invalid LLM output")