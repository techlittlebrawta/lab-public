import json, os, urllib.request
BASE = os.environ["PNETLAB_URL"].rstrip("/")
TOKEN = os.environ.get("PNETLAB_TOKEN")
def request(path, method="GET", body=None):
    headers = {"Accept":"application/json","Content-Type":"application/json"}
    if TOKEN: headers["Authorization"] = f"Bearer {TOKEN}"
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(f"{BASE}/{path.lstrip('/')}", data=data, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=30) as response:
        return json.loads(response.read().decode())
if __name__ == "__main__": print(json.dumps(request("api/status"), indent=2))