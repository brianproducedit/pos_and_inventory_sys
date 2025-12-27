# Paynow integration
# Use Paynow API to initiate payments

import requests
import os
from dotenv import load_dotenv

load_dotenv()

PAYNOW_INTEGRATION_ID = os.getenv("PAYNOW_INTEGRATION_ID")
PAYNOW_INTEGRATION_KEY = os.getenv("PAYNOW_INTEGRATION_KEY")

def initiate_payment(amount: float, reference: str):
    if not PAYNOW_INTEGRATION_ID or not PAYNOW_INTEGRATION_KEY:
        raise ValueError("Paynow credentials not set in environment variables")
    # Placeholder API call
    url = "https://www.paynow.co.zw/interface/initiatetransaction"
    return_url = os.getenv('PAYNOW_RETURN_URL', 'http://localhost:8000/paynow/callback')
    result_url = os.getenv('PAYNOW_RESULT_URL', 'http://localhost:8000/paynow/callback')

    data = {
        "id": PAYNOW_INTEGRATION_ID,
        "reference": reference,
        "amount": amount,
        "additionalinfo": "POS Sale",
        "returnurl": return_url,
        "resulturl": result_url,
    }
    response = requests.post(url, data=data)
    return response.json()

# Add callback endpoint in main.py or router