import json

# Import the CHIP clusters
from chip.clusters import Objects as clusters

# Import the ability to turn objects into dictionaries, and vice-versa
from matter_server.common.helpers.util import dataclass_from_dict, dataclass_to_dict

from matter_server.client import MatterClient

command = clusters.OnOff.Commands.On()
payload = dataclass_to_dict(command)

cd

message = {
    "message_id": "2",
    "command": "read_attribute",
    "args": {
       "node_id": 73,
       "attribute_path": "2/1026/0"
    },
}

print(json.dumps(message, indent=2))