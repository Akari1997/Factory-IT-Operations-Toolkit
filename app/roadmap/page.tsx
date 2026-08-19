import RoadmapCanvas from "@/components/roadmap/RoadmapCanvas";
import { loadRoadmap, toFlow } from "@/lib/roadmap/transform";

export default function RoadmapPage() {
  const data = loadRoadmap();
  const { nodes, edges } = toFlow(data);

  return <RoadmapCanvas initialNodes={nodes} initialEdges={edges} title={data.title} />;
}
