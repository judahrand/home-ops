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

for thermostat_node_id, (temperature_node_id, endpoint_id) in BINDINGS.items():
    attribute_path = f"{endpoint_id}/1026/0"
    message = {
       "message_id": str(MESSAGE_NUMBER),
       "command": "read_attribute",
       "args": {
          "node_id": temperature_node_id,
          "attribute_path": attribute_path,
       },
    }
    ws.send(json.dumps(message))
    result = json.loads(ws.recv())
    print(f"Temperature sensor {(temperature_node_id, endpoint_id)}: {result["result"][attribute_path]}")
    MESSAGE_NUMBER += 1

    attribute_path = "1/513/0"
    message = {
       "message_id": str(MESSAGE_NUMBER),
       "command": "read_attribute",
       "args": {
            "node_id": thermostat_node_id,
            "attribute_path": attribute_path,
       },
    }
    ws.send(json.dumps(message))
    result = json.loads(ws.recv())
    print(f"Thermostat ({thermostat_node_id}): {result["result"][attribute_path]}")
    MESSAGE_NUMBER += 1

    print("\n")

ws.close()
