def generate_html(ddr):
    html = "<h1>DDR Report</h1>"

    html += f"<h2>Summary</h2><p>{ddr.property_issue_summary}</p>"

    for obs in ddr.area_wise_observations:
        html += f"<h3>{obs.area}</h3>"
        html += "<ul>"
        for i in obs.inspection_observations:
            html += f"<li>{i}</li>"
        html += "</ul>"

    return html