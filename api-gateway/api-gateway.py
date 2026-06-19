# =============================================================================
# api-gateway.py — FastAPI Gateway Service
#
# WHAT THIS SERVICE DOES:
#   Acts as a middleman between the user and the OCR model server.
#
#   Request flow:
#     1. User sends an image file to this gateway (port 8001)
#     2. Gateway reads the image and converts it to base64 text
#     3. Gateway sends the base64 image to the KServe OCR model (port 8080)
#     4. OCR model extracts text from the image and returns it
#     5. Gateway sends the extracted text back to the user
#
# WHY A GATEWAY?
#   The KServe model server speaks a specific format (V2 inference protocol)
#   The gateway hides this complexity — users just send a simple image file
# =============================================================================

from fastapi import FastAPI, File, UploadFile, HTTPException
from fastapi.responses import JSONResponse
import requests
import base64
import json
import os

# Create the FastAPI application
app = FastAPI()

# -----------------------------------------------------------------------
# WHERE IS THE OCR MODEL SERVER?
#
# We read this from an environment variable called KSERVE_URL
# This makes the gateway flexible — same code works everywhere:
#
#   Local testing  → export KSERVE_URL=http://localhost:8080/v2/models/ocr-model/infer
#   Docker         → docker run -e KSERVE_URL=http://ocr-model-container:8080/...
#   Kubernetes     → set in ConfigMap → http://ocr-model-service:8080/...
#
# If KSERVE_URL is not set, it defaults to localhost (for local testing)
# -----------------------------------------------------------------------
KSERVE_URL = os.getenv(
    "KSERVE_URL",
    "http://localhost:8080/v2/models/ocr-model/infer"  # default for local testing
)


@app.post("/gateway/ocr")
async def gateway_ocr_request(image_file: UploadFile = File(...)):
    """
    Accepts an image file upload and returns the extracted text.

    How to call this endpoint:
        POST http://localhost:8001/gateway/ocr
        Body: form-data
        Key:  image_file (type: File)
        Value: your image file (.png or .jpg)
    """
    try:
        # ------------------------------------------------------------------
        # STEP 1: Read the uploaded image file as raw bytes
        # UploadFile is the image the user sent — we read its content here
        # ------------------------------------------------------------------
        image_data = await image_file.read()

        # ------------------------------------------------------------------
        # STEP 2: Convert image bytes to base64 string
        # KServe model server expects data as base64 encoded text
        # base64 turns binary data into a safe text format for JSON transfer
        # ------------------------------------------------------------------
        base64_image_data = base64.b64encode(image_data).decode('utf-8')

        # ------------------------------------------------------------------
        # STEP 3: Build the request body for KServe
        # KServe uses the V2 inference protocol — this is the required format
        # ------------------------------------------------------------------
        infer_request = {
            "inputs": [
                {
                    "name": "input-0",              # name of the input tensor
                    "shape": [1],                   # we are sending 1 image
                    "datatype": "BYTES",            # data type is bytes
                    "data": [base64_image_data],    # the actual image data
                    "parameters": {
                        "content_type": image_file.content_type  # e.g. image/png
                    }
                }
            ]
        }

        # ------------------------------------------------------------------
        # STEP 4: Convert the request dictionary to a JSON string
        # HTTP requests send data as text — json.dumps converts dict to text
        # ------------------------------------------------------------------
        json_request = json.dumps(infer_request)

        # ------------------------------------------------------------------
        # STEP 5: Set the Content-Type header
        # This tells the KServe server that we are sending JSON data
        # ------------------------------------------------------------------
        headers = {'Content-Type': 'application/json'}

        # ------------------------------------------------------------------
        # STEP 6: Send the request to the KServe OCR model server
        # This is where the actual OCR processing happens
        # ------------------------------------------------------------------
        response = requests.post(KSERVE_URL, headers=headers, data=json_request)

        # ------------------------------------------------------------------
        # STEP 7: Check if KServe returned an error
        # 200 means success — anything else means something went wrong
        # ------------------------------------------------------------------
        if response.status_code != 200:
            raise HTTPException(
                status_code=response.status_code,
                detail=response.text
            )

        # ------------------------------------------------------------------
        # STEP 8: Return the OCR result to the user
        # The response contains the text extracted from the image
        # ------------------------------------------------------------------
        return JSONResponse(content=response.json())

    except HTTPException as http_exc:
        # Re-raise HTTP errors from KServe as-is
        raise http_exc

    except Exception as e:
        # Catch any unexpected errors and return a 500 error with the message
        raise HTTPException(status_code=500, detail=str(e))


# Run the FastAPI app when this file is executed directly
# host="0.0.0.0" means accept connections from any IP (needed inside Docker)
# port=8001 is the port this gateway listens on
if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8001)
