import json
from sys import stdin, stdout


procedures = {}

def rpc(name):
    global procedures
    def wrapper(function):
        procedures[name] = function
        return function
    return wrapper


def response(**data):
    print(json.dumps(data))
    stdout.flush()


def run():
    for line in stdin:
        data = json.loads(line)

        metadata = data["rpc"]
        operation = metadata["op"]

        if operation == "call":
            name = data["procedure"]
            if name not in procedures:
                response(
                    rpc={"op": "error"},
                    message=f"invalid_procedure: {name}"
                )
                continue

            procedure = procedures[name]
            args = data["args"]
            kwargs = data["kwargs"]

            try:
                response(
                    rpc={"op": "return"},
                    result=procedure(*args, **kwargs)
                )
            except Exception as ex:
                cls = ex.__class__.__name__
                response(
                    rpc={"op": "error"},
                    message=f"{cls}: {ex}"
                )
            continue