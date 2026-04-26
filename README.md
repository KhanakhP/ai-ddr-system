# 🏗️ AI-Based DDR (Detailed Diagnostic Report) Generator

## 📌 Overview

This project generates a **structured DDR (Detailed Diagnostic Report)** from:

* 📄 Inspection Reports
* 🌡️ Thermal Imaging Reports

The system extracts information from PDFs, processes it, and uses an LLM (Gemini) to produce a **clean, client-ready diagnostic report**.

---

## 🚀 Key Features

* 📑 **PDF Parsing**

  * Extracts text and images using PyMuPDF

* 🧠 **LLM-Based Reasoning**

  * Uses Gemini (via LangChain) to analyze inspection + thermal data

* 🧩 **Structured Output**

  * Enforces schema using Pydantic
  * Generates consistent DDR format

* ⚠️ **Schema Correction Layer**

  * Fixes incomplete/misaligned LLM outputs automatically

* 🔁 **Retry Handling**

  * Handles incomplete JSON responses from LLM

* 🖼️ **Image Integration**

  * Associates extracted images with observations

* 🌐 **HTML Report Generation**

  * Produces readable DDR report

---

## 🧠 System Architecture

```
Input PDFs
   ↓
PDF Parser (text + images)
   ↓
Text Structuring
   ↓
LLM Reasoning (Gemini)
   ↓
Schema Validation (Pydantic)
   ↓
Image Mapping
   ↓
HTML Report Output
```

---

## 🛠️ Tech Stack

* **Language:** Python
* **PDF Processing:** PyMuPDF
* **LLM:** Gemini (via LangChain)
* **Validation:** Pydantic
* **Environment Management:** python-dotenv

---

## 📁 Project Structure

```
ai_ddr_system/
│
├── app/
│   └── main.py
│
├── modules/
│   ├── parser/
│   ├── processor/
│   ├── merger/
│   ├── reasoning/
│   ├── generator/
│   ├── image_mapper/
│   ├── output/
│
├── data/
│   ├── input/
│   ├── images/
│   ├── output/
│
├── requirements.txt
└── README.md
```

---

## ⚙️ Setup Instructions

### 1. Clone the repository

```bash
git clone https://github.com/your-username/ai-ddr-system.git
cd ai-ddr-system
```

---

### 2. Create virtual environment

```bash
python -m venv .venv
.venv\Scripts\activate   # Windows
```

---

### 3. Install dependencies

```bash
pip install -r requirements.txt
```

---

### 4. Add API Key

Create a `.env` file in root:

```
GOOGLE_API_KEY=your_gemini_api_key
```

---

### 5. Add input files

Place PDFs in:

```
data/input/
```

Example:

* `inspection.pdf`
* `thermal.pdf`

---

### 6. Run the project

```bash
python -m app.main
```

---

## 📄 Output

After execution:

```
data/output/report.html
```

Open in browser to view the generated DDR.

---

## ⚠️ Known Limitations

* Large input text may cause LLM truncation
* Image mapping is basic (non-semantic)
* Conflict detection is minimal
* Output quality depends on LLM consistency

---

## 🔮 Future Improvements

* Chunk-based processing (for large documents)
* Advanced conflict detection logic
* Semantic image-to-text mapping
* Vector database integration (FAISS)
* Multi-step reasoning pipeline

---

## 👨‍💻 Author

**Khanakh Prajapati**
B.Tech IT | AI/ML Enthusiast

This project focuses on **system design + structured LLM reasoning**, not just API usage.
It demonstrates how to build a **robust pipeline around unreliable LLM outputs**.
