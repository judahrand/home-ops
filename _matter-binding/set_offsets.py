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

for thermostat_node_id, _ in BINDINGS.items():
    attribute_path = f"1/513/16"
    message = {
       "message_id": str(MESSAGE_NUMBER),
       "command": "write_attribute",
       "args": {
          "node_id": thermostat_node_id,
          "attribute_path": attribute_path,
          "value": -20,
       },
    }
    ws.send(json.dumps(message))
    result = json.loads(ws.recv())
    print(result)
    MESSAGE_NUMBER += 1

    print("\n")

ws.close()
