from pydantic import BaseModel
from typing import List

class Observation(BaseModel):
    area: str
    inspection_observations: List[str]
    thermal_findings: List[str]
    combined_finding: str
    images: List[str]

class DDR(BaseModel):
    property_issue_summary: str
    area_wise_observations: List[Observation]
    probable_root_cause: List[str]
    severity_assessment: dict
    recommended_actions: List[str]
    additional_notes: List[str]