import { readFileSync } from "node:fs";
import { join } from "node:path";
import YAML from "yaml";
import { Edge, Node } from "reactflow";

type StatusOption = {
  id: string;
  label: string;
  icon: string;
  color: string;
};

type ModuleItem = {
  id: string;
  title: string;
  required?: boolean;
  links?: { page?: string };
};

type Domain = {
  id: string;
  name: string;
  modules: ModuleItem[];
};

type RoadmapData = {
  id: string;
  title: string;
  settings: { default_status: string };
  status_options: StatusOption[];
  training_domains: Domain[];
};

export type RoadmapNodeData = {
  label: string;
  domainName: string;
  required: boolean;
  status: string;
  link?: string;
};

export function loadRoadmap(): RoadmapData {
  const filePath = join(process.cwd(), "content", "roadmap.yaml");
  const raw = readFileSync(filePath, "utf-8");
  return YAML.parse(raw) as RoadmapData;
}

export function toFlow(data: RoadmapData): { nodes: Node<RoadmapNodeData>[]; edges: Edge[] } {
  const nodes: Node<RoadmapNodeData>[] = [];
  const edges: Edge[] = [];

  const domainXGap = 420;
  const rowYGap = 120;
  const startX = 120;
  const startY = 120;

  data.training_domains.forEach((domain, dIndex) => {
    const x = startX + dIndex * domainXGap;

    domain.modules.forEach((m, i) => {
      const y = startY + i * rowYGap;
      const nodeId = `${domain.id}__${m.id}`;

      nodes.push({
        id: nodeId,
        position: { x, y },
        data: {
          label: m.title,
          domainName: domain.name,
          required: !!m.required,
          status: data.settings.default_status,
          link: m.links?.page || "",
        },
        type: "default",
      });

      if (i > 0) {
        const prevId = `${domain.id}__${domain.modules[i - 1].id}`;
        edges.push({
          id: `e-${prevId}-${nodeId}`,
          source: prevId,
          target: nodeId,
          animated: false,
          style: { stroke: "#64748b", strokeWidth: 2 },
        });
      }
    });

    if (dIndex > 0 && domain.modules.length > 0) {
      const prevDomain = data.training_domains[dIndex - 1];
      if (prevDomain.modules.length > 0) {
        const prevTail = `${prevDomain.id}__${prevDomain.modules[prevDomain.modules.length - 1].id}`;
        const currentHead = `${domain.id}__${domain.modules[0].id}`;
        edges.push({
          id: `cross-${prevTail}-${currentHead}`,
          source: prevTail,
          target: currentHead,
          animated: true,
          style: { stroke: "#a78bfa", strokeWidth: 2 },
        });
      }
    }
  });

  return { nodes, edges };
}
