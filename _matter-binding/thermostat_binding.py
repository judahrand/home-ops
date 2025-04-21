import json

from websocket import create_connection

MATTER_URL = "ws://matter.judahrand.net:5580/ws"
TEMPERATURE_NODE_ID = 77
BINDINGS = {
    67: (TEMPERATURE_NODE_ID, 2),  # Bedroom
    84: (TEMPERATURE_NODE_ID, 3),  # Living Room
    82: (TEMPERATURE_NODE_ID, 4),  # Office
    83: (TEMPERATURE_NODE_ID, 5),  # Dining Room
}

MESSAGE_NUMBER = 1


ws = create_connection(MATTER_URL)
result = json.loads(ws.recv())
print(result)
FABRIC_ID = result["fabric_id"]

print("Writing ACL attribute to Temperature Sensor...")
acls = [
    {
        "fabricIndex": FABRIC_ID,
        "privilege": 5,
        "authMode": 2,
        "subjects": [112233],
        "targets": None,
    },
    *(
        {
            "fabricIndex": FABRIC_ID,
            "privilege": 1,
            "authMode": 2,
            "subjects": [thermostat_node_id],
            "targets": [
                {
                    "cluster": 1026,
                    "endpoint": endpoint_id,
                    "deviceType": None,
                },
            ],
        }
        for thermostat_node_id, (_, endpoint_id) in BINDINGS.items()
    ),
]
message = {
   "message_id": str(MESSAGE_NUMBER),
   "command": "write_attribute",
   "args": {
        "node_id": TEMPERATURE_NODE_ID,
        "attribute_path": "0/31/0",
        "value": acls,
    },
}
ws.send(json.dumps(message))
result = json.loads(ws.recv())
print(result)
MESSAGE_NUMBER += 1


for thermostat_node_id, (temperature_node_id, endpoint_id) in BINDINGS.items():
    print("Create binding from Thermostat to Temperature Sensor...")
    message = {
    "message_id": str(MESSAGE_NUMBER),
    "command": "write_attribute",
    "args": {
            "node_id": thermostat_node_id,
            "attribute_path": "1/30/0",
            "value": [
                {
                    "fabricIndex": FABRIC_ID,
                    "node": temperature_node_id,
                    "endpoint": endpoint_id,
                    "cluster": 1026,
                },
            ],
        },
    }
    ws.send(json.dumps(message))
    result = json.loads(ws.recv())
    print(result)
    MESSAGE_NUMBER += 1

    print("Set RemoteSensing attribute (26) value...")
    message = {
        "message_id": str(MESSAGE_NUMBER),
        "command": "write_attribute",
        "args": {
            "node_id": thermostat_node_id,
            "attribute_path": "1/513/26",
            "value": 1,
        },
    }
    ws.send(json.dumps(message))
    result = json.loads(ws.recv())
    print(result)
    MESSAGE_NUMBER += 1

ws.close()
