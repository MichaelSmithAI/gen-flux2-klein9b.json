import argparse
import base64
import json
import mimetypes
from pathlib import Path


def data_url_for_image(path: Path) -> str:
    mime, _ = mimetypes.guess_type(path.name)
    if not mime:
        mime = "application/octet-stream"
    data = base64.b64encode(path.read_bytes()).decode("ascii")
    return f"data:{mime};base64,{data}"


def convert_workflow(ui_workflow: dict) -> dict:
    links_by_id = {link[0]: link for link in ui_workflow.get("links", [])}
    prompt = {}

    for node in ui_workflow.get("nodes", []):
        node_id = str(node.get("id"))
        node_inputs = {}

        inputs_def = {inp["name"]: inp for inp in node.get("inputs", [])}
        widget_names = [
            inp["name"]
            for inp in node.get("inputs", [])
            if "widget" in inp and inp.get("type") != "IMAGEUPLOAD"
        ]
        widget_values = node.get("widgets_values", []) or []

        proxy_widgets = node.get("properties", {}).get("proxyWidgets")
        if proxy_widgets:
            for idx, entry in enumerate(proxy_widgets):
                if idx >= len(widget_values):
                    break
                name = entry[1]
                inp_def = inputs_def.get(name)
                if not inp_def or inp_def.get("link") is not None:
                    continue
                if name in widget_names:
                    node_inputs[name] = widget_values[idx]
        else:
            for idx, name in enumerate(widget_names):
                if idx >= len(widget_values):
                    break
                inp_def = inputs_def.get(name)
                if inp_def and inp_def.get("link") is None:
                    node_inputs[name] = widget_values[idx]

        for inp in node.get("inputs", []):
            link_id = inp.get("link")
            if link_id is None:
                continue
            link = links_by_id.get(link_id)
            if not link:
                continue
            from_node_id = str(link[1])
            from_slot = link[2]
            node_inputs[inp["name"]] = [from_node_id, from_slot]

        prompt[node_id] = {"class_type": node.get("type"), "inputs": node_inputs}

    return prompt


def main() -> None:
    parser = argparse.ArgumentParser(description="Build test request JSON from ComfyUI workflow.")
    parser.add_argument("--workflow", default="Flux2-Klein_00248_.json")
    parser.add_argument("--prompt", required=True)
    parser.add_argument("--image1", required=True)
    parser.add_argument("--image2")
    parser.add_argument("--out", default="input-req.json")
    args = parser.parse_args()

    workflow_path = Path(args.workflow)
    image1_path = Path(args.image1)
    image2_path = Path(args.image2) if args.image2 else image1_path

    ui_workflow = json.loads(workflow_path.read_text(encoding="utf-8"))
    prompt = convert_workflow(ui_workflow)

    load_image_nodes = [node_id for node_id, node in prompt.items() if node["class_type"] == "LoadImage"]
    image_names = [image1_path.name, image2_path.name]
    for idx, node_id in enumerate(load_image_nodes):
        prompt[node_id]["inputs"]["image"] = image_names[min(idx, len(image_names) - 1)]

    for node in prompt.values():
        if "text" in node["inputs"] and isinstance(node["inputs"]["text"], str):
            node["inputs"]["text"] = args.prompt

    images = [
        {"name": image1_path.name, "image": data_url_for_image(image1_path)},
    ]
    if image2_path != image1_path:
        images.append({"name": image2_path.name, "image": data_url_for_image(image2_path)})

    output = {"input": {"workflow": prompt, "images": images}}
    Path(args.out).write_text(json.dumps(output, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
