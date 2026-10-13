"""Snapshot the project's visual assets through read-only MCP for Rojo builds.

Mesh URLs, transforms, primary parts, welds, particles and material variants are
stored in XML. Rojo itself encodes the typed attribute payloads. This
does not download media or modify/publish the open place.
"""
from pathlib import Path
import importlib.util
import json
import sys
import subprocess
import xml.etree.ElementTree as ET

sys.stdout.reconfigure(encoding="utf-8")
ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("mcp_sync", ROOT / "scripts/mcp_sync.py")
sync = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync)

CODE = r'''
local roots = { game.ReplicatedStorage:WaitForChild("Assets"), game.MaterialService:WaitForChild("AssistantMaterials") }
local ids = {}
local objects = {}
local nextId = 0
for _, root in roots do
    nextId += 1 ids[root] = "RBX" .. nextId objects[nextId] = root
    for _, object in root:GetDescendants() do nextId += 1 ids[object] = "RBX" .. nextId objects[nextId] = object end
end
local fields = {
    Folder = {}, Model = {"PrimaryPart"},
    MeshPart = {"MeshId", "TextureID", "RenderFidelity", "DoubleSided"},
    Part = {"Shape"},
    SpecialMesh = {"MeshId", "TextureId", "MeshType", "Scale", "Offset", "VertexColor"},
    ManualWeld = {"Part0", "Part1", "C0", "C1", "Enabled"},
    PointLight = {"Brightness", "Color", "Range", "Enabled", "Shadows"},
    ParticleEmitter = {"Texture", "Color", "Size", "Transparency", "Rate", "Lifetime", "Speed", "Rotation", "RotSpeed", "SpreadAngle", "Acceleration", "Drag", "Enabled", "LightEmission", "LightInfluence", "EmissionDirection", "Orientation", "ZOffset", "LockedToPart", "VelocityInheritance", "TimeScale", "Squash"},
    MaterialVariant = {"BaseMaterial", "ColorMap", "NormalMap", "RoughnessMap", "MetalnessMap", "StudsPerTile"},
}
local partFields = {"Anchored", "CanCollide", "CanQuery", "CanTouch", "Massless", "CastShadow", "Size", "CFrame", "Color", "Material", "MaterialVariant", "Transparency", "Reflectance", "TopSurface", "BottomSurface"}
local content = {MeshId=true, TextureID=true, TextureId=true, Texture=true, ColorMap=true, NormalMap=true, RoughnessMap=true, MetalnessMap=true}
local function encode(value, name)
    local kind = typeof(value)
    if value == nil then return {kind="Ref", value="null"} end
    if kind == "Instance" then
        assert(ids[value], "asset reference outside snapshot: " .. value:GetFullName())
        return {kind="Ref", value=ids[value]}
    elseif kind == "boolean" then return {kind="bool", value=value}
    elseif kind == "string" then return {kind=if content[name] then "Content" else "string", value=value}
    elseif kind == "number" then return {kind="double", value=value}
    elseif kind == "EnumItem" then return {kind="token", value=value.Value}
    elseif kind == "Vector3" then return {kind="Vector3", value={value.X,value.Y,value.Z}}
    elseif kind == "Vector2" then return {kind="Vector2", value={value.X,value.Y}}
    elseif kind == "Color3" then return {kind="Color3", value={value.R,value.G,value.B}}
    elseif kind == "CFrame" then return {kind="CoordinateFrame", value={value:GetComponents()}}
    elseif kind == "NumberRange" then return {kind="NumberRange", value={value.Min,value.Max}}
    elseif kind == "NumberSequence" then
        local list={} for _, point in value.Keypoints do table.insert(list,point.Time) table.insert(list,point.Value) table.insert(list,point.Envelope) end
        return {kind="NumberSequence",value=list}
    elseif kind == "ColorSequence" then
        local list={} for _, point in value.Keypoints do table.insert(list,point.Time) table.insert(list,point.Value.R) table.insert(list,point.Value.G) table.insert(list,point.Value.B) table.insert(list,0) end
        return {kind="ColorSequence",value=list}
    end
    error("unsupported snapshot property " .. name .. ": " .. kind)
end
local visited = 0
local function snapshot(object)
    local names=assert(fields[object.ClassName], "unsupported asset class: " .. object.ClassName)
    local properties = {Name={kind="string",value=object.Name}}
    for _, name in names do properties[name]=encode(object[name], name) end
    if object:IsA("BasePart") then for _, name in partFields do properties[name]=encode(object[name],name) end end
    local attributes={}
    for name,value in object:GetAttributes() do
        local kind=typeof(value)
        assert(kind=="string" or kind=="boolean" or kind=="number", "unsupported attribute: " .. name)
        attributes[name]={[if kind=="string" then "String" elseif kind=="boolean" then "Bool" else "Float64"]=value}
    end
    local children={}
    visited += 1 if visited % 100 == 0 then task.wait() end
    for _, child in object:GetChildren() do table.insert(children,ids[child]) end
    return {class=object.ClassName,id=ids[object],name=object.Name,properties=properties,attributes=attributes,children=children}
end
local output={} for index=START_INDEX, math.min(END_INDEX,#objects) do table.insert(output,snapshot(objects[index])) end
return game.HttpService:JSONEncode({nodes=output,total=#objects,roots={ids[roots[1]],ids[roots[2]]}})
'''

def item(parent, node):
    element = ET.SubElement(parent, "Item", {"class": node["class"], "referent": node["id"]})
    properties = ET.SubElement(element, "Properties")
    for name, prop in node["properties"].items():
        kind, value = prop["kind"], prop["value"]
        entry = ET.SubElement(properties, kind, {"name": name})
        if kind == "Content":
            ET.SubElement(entry, "url" if value else "null").text = value or None
        elif kind in ("Vector3", "Vector2", "Color3", "CoordinateFrame"):
            keys = {"Vector3": ["X", "Y", "Z"], "Vector2": ["X", "Y"], "Color3": ["R", "G", "B"],
                    "CoordinateFrame": ["X", "Y", "Z", "R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22"]}[kind]
            for key, number in zip(keys, value): ET.SubElement(entry, key).text = str(number)
        elif isinstance(value, list):
            entry.text = " ".join(map(str, value)) + " "
        else:
            entry.text = str(value).lower() if isinstance(value, bool) else str(value)
    for child in node["children"]: item(element, child)

def main():
    mcp = sync.Mcp()
    try:
        sid = mcp.studio_id()
        state = mcp.tool("get_studio_state", {"studio_id": sid})
        assert "Available DataModels: Edit" in state, "stop play before exporting"
        flat = []
        start = 1
        while True:
            code = CODE.replace("START_INDEX", str(start)).replace("END_INDEX", str(start + 19))
            chunk = json.loads(mcp.tool("execute_luau", {"studio_id": sid, "datamodel_type": "Edit", "code": code}))
            flat.extend(chunk["nodes"])
            start += 20
            if start > chunk["total"]: break
        by_id = {node["id"]: node for node in flat}
        for node in flat:
            node["children"] = [by_id[cid] for cid in node["children"]]
        nodes = [by_id[rid] for rid in chunk["roots"]]
    finally:
        mcp.close()
    # Ask the pinned Rojo encoder to serialize Attributes; do not approximate
    # Roblox's binary format or overlay duplicate children onto an XML source.
    scratch = ROOT / ".luau"
    scratch.mkdir(exist_ok=True)
    attribute_project = {"name": "AssetAttributes", "tree": {"$className": "Folder"}}
    for node in flat:
        if node["attributes"]:
            attribute_project["tree"][node["id"]] = {"$className": node["class"], "$properties": {"Attributes": node["attributes"]}}
    meta_path = scratch / "asset-attributes.project.json"
    blob_path = scratch / "asset-attributes.rbxmx"
    meta_path.write_text(json.dumps(attribute_project), encoding="utf-8")
    subprocess.run(["rojo", "build", str(meta_path), "-o", str(blob_path)], check=True, capture_output=True)
    attribute_blobs = {}
    for element in ET.parse(blob_path).getroot().iter("Item"):
        props = element.find("Properties")
        name = props.find("string[@name='Name']")
        blob = props.find("BinaryString[@name='AttributesSerialize']")
        if name is not None and blob is not None: attribute_blobs[name.text] = blob.text
    assert len(attribute_blobs) == sum(bool(node["attributes"]) for node in flat), "missing attribute serialization"
    folder = ROOT / "assets"
    folder.mkdir(exist_ok=True)
    project_path = ROOT / "default.project.json"
    project = json.loads(project_path.read_text(encoding="utf-8"))
    for node, service in zip(nodes, ("ReplicatedStorage", "MaterialService")):
        document = ET.Element("roblox", {"version": "4"})
        item(document, node)
        for element in document.iter("Item"):
            blob = attribute_blobs.get(element.get("referent"))
            if blob is not None:
                ET.SubElement(element.find("Properties"), "BinaryString", {"name": "AttributesSerialize"}).text = blob
        ET.indent(document)
        path = folder / (node["name"] + ".rbxmx")
        ET.ElementTree(document).write(path, encoding="utf-8", xml_declaration=True)
        tree = project["tree"].setdefault(service, {})
        tree[node["name"]] = {"$path": path.relative_to(ROOT).as_posix()}
        print(f"exported {path.name}: {len(list(document.iter('Item')))} instances")
    project_path.write_text(json.dumps(project, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

if __name__ == "__main__": main()
