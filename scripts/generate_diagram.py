"""Generates docs/architecture.drawio for the Private Access to Foundation
Models project using drawpyo.

Run with: python3 scripts/generate_diagram.py

Icon/color notes:
- Confirmed AWS4 resIcon names are used for everything that has one
  (lambda_function, dynamodb, machine_learning, security_group).
- There is no confirmed resIcon for a VPC interface endpoint / PrivateLink
  endpoint, so the "Endpoint", "Policy", and "Routes traffic" nodes fall back
  to the security_group icon (a reasonable stand-in for a network
  access-control / routing resource), styled in the networking color below.
- Category colors: Compute (Lambda) #ED7100, Database (DynamoDB) #C925D1,
  Artificial Intelligence (foundation models) #01A88D, generic/neutral
  #232F3E. Networking/VPC elements (endpoints, the private connection) use
  #8C4FFF, a common AWS4 networking purple, chosen for consistency across
  this diagram since no single official "VPC endpoint" color is mandated.
- Boundary groups (AWS Cloud > Region > VPC > Private subnet) are drawn as
  nested mxgraph.aws4.group containers using absolute page coordinates, so
  each inner rectangle sits fully inside its parent rectangle's bounds.
"""
import os

import drawpyo

OUTPUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "docs")

AWS4_BASE = (
    "sketch=0;outlineConnect=0;fontColor=#232F3E;gradientColor=none;strokeColor=none;"
    "dashed=0;verticalLabelPosition=bottom;verticalAlign=top;align=center;html=1;"
    "fontSize=11;fontStyle=0;aspect=fixed;pointerEvents=1;"
)

NETWORK_COLOR = "#8C4FFF"


def aws_style(icon_name, fill_color):
    return f"{AWS4_BASE}fillColor={fill_color};shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.{icon_name};"


def add_node(page, name, x, y, icon_name, fill_color, width=64, height=64):
    node = drawpyo.diagram.Object(page=page, value=name)
    node.position = (x, y)
    node.geometry.width = width
    node.geometry.height = height
    node.apply_style_string(aws_style(icon_name, fill_color))
    return node


def add_group(page, name, x, y, width, height, stroke_color):
    group = drawpyo.diagram.Object(page=page, value=name)
    group.position = (x, y)
    group.geometry.width = width
    group.geometry.height = height
    group.apply_style_string(
        "shape=mxgraph.aws4.group;grIcon=mxgraph.aws4.group_security_group;"
        f"strokeColor={stroke_color};fillColor=none;verticalAlign=top;align=left;"
        f"spacingLeft=30;fontColor={stroke_color};dashed=1;"
    )
    return group


def add_edge(page, source, target, label=None):
    edge = drawpyo.diagram.Edge(page=page, source=source, target=target, label=label)
    edge.waypoints = "orthogonal"
    edge.endArrow = "block"
    edge.startArrow = "none"
    edge.strokeColor = "#545B64"
    return edge


def build_diagram():
    file = drawpyo.File()
    file.file_name = "architecture.drawio"
    file.file_path = OUTPUT_DIR

    page = drawpyo.Page(file=file)
    page.name = "Private Access to Foundation Models"

    # ─── Nested boundary groups: AWS Cloud > Region > VPC > Private subnet ──
    add_group(page, "AWS Cloud", 20, 20, 1180, 520, "#232F3E")
    add_group(page, "Region: us-east-1", 50, 60, 1120, 460, "#DD344C")

    add_group(page, "VPC #1", 80, 110, 480, 380, NETWORK_COLOR)
    add_group(page, "Private subnet", 110, 160, 420, 310, "#AAB7B8")

    add_group(page, "VPC #2", 640, 110, 480, 380, NETWORK_COLOR)
    add_group(page, "Private subnet", 670, 160, 420, 310, "#AAB7B8")

    # ─── VPC #1: serverless application + customer database + Endpoint ──────
    serverless_app = add_node(page, "Serverless application\n(Lambda)", 150, 200, "lambda_function", "#ED7100")
    customer_db = add_node(page, "Customer database\n(DynamoDB)", 150, 380, "dynamodb", "#C925D1")
    endpoint = add_node(page, "Endpoint", 400, 200, "security_group", NETWORK_COLOR)
    policy = add_node(page, "Policy", 420, 350, "security_group", "#DD344C", width=48, height=48)

    # ─── VPC #2: routing + Access FM models endpoint ─────────────────────────
    router = add_node(page, "Routes traffic\n(Route table)", 710, 200, "security_group", "#AAB7B8")
    fm_access = add_node(page, "Access FM models\n(Bedrock VPC endpoint)", 960, 200, "machine_learning", "#01A88D")

    add_edge(page, serverless_app, customer_db, "Fetch customer data")
    add_edge(page, serverless_app, endpoint, "Invoke model")
    add_edge(page, policy, endpoint, "Governs")

    # Private connection: crosses from VPC #1's Endpoint to VPC #2's router.
    private_connection = add_edge(page, endpoint, router, "Private connection\n(PrivateLink / VPC peering)")
    private_connection.strokeColor = NETWORK_COLOR

    add_edge(page, router, fm_access, "Routes traffic")

    os.makedirs(OUTPUT_DIR, exist_ok=True)
    file.write()
    print(f"Wrote {os.path.join(OUTPUT_DIR, file.file_name)}")


if __name__ == "__main__":
    build_diagram()
