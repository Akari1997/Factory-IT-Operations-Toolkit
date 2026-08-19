"use client";

import { useMemo, useState } from "react";
import ReactFlow, {
  Background,
  Controls,
  MiniMap,
  Node,
  Edge,
  MarkerType,
} from "reactflow";
import "reactflow/dist/style.css";
import type { RoadmapNodeData } from "@/lib/roadmap/transform";

type Props = {
  initialNodes: Node<RoadmapNodeData>[];
  initialEdges: Edge[];
  title: string;
};

const statusColorMap: Record<string, string> = {
  not_started: "#6b7280",
  learning: "#a855f7",
  done: "#22c55e",
  skip: "#9ca3af",
};

export default function RoadmapCanvas({ initialNodes, initialEdges, title }: Props) {
  const [selected, setSelected] = useState<Node<RoadmapNodeData> | null>(null);

  const edges = useMemo(
    () =>
      initialEdges.map((e) => ({
        ...e,
        markerEnd: { type: MarkerType.ArrowClosed, color: e.animated ? "#a78bfa" : "#64748b" },
      })),
    [initialEdges]
  );

  return (
    <div className="h-[92vh] w-full bg-[#0b1020] text-slate-100">
      <div className="border-b border-slate-800 px-6 py-4 text-lg font-semibold">{title}</div>

      <div className="relative h-[calc(92vh-64px)]">
        <ReactFlow
          nodes={initialNodes}
          edges={edges}
          fitView
          onNodeClick={(_, node) => setSelected(node)}
          proOptions={{ hideAttribution: true }}
          defaultEdgeOptions={{ type: "smoothstep" }}
        >
          <Background gap={24} color="#1f2a44" />
          <MiniMap
            pannable
            zoomable
            nodeColor={(n) => statusColorMap[(n.data as RoadmapNodeData).status] ?? "#64748b"}
            maskColor="rgba(2,6,23,0.6)"
          />
          <Controls />
        </ReactFlow>

        {selected && (
          <aside className="absolute right-4 top-4 w-80 rounded-xl border border-slate-700 bg-slate-900/95 p-4 shadow-2xl">
            <h3 className="text-base font-semibold">{selected.data.label}</h3>
            <p className="mt-1 text-sm text-slate-300">{selected.data.domainName}</p>

            <div className="mt-3 flex items-center gap-2 text-sm">
              <span className="text-slate-400">Required:</span>
              <span className={selected.data.required ? "text-emerald-400" : "text-slate-400"}>
                {selected.data.required ? "Yes" : "No"}
              </span>
            </div>

            <div className="mt-2 flex items-center gap-2 text-sm">
              <span className="text-slate-400">Status:</span>
              <span
                className="inline-block h-2.5 w-2.5 rounded-full"
                style={{ background: statusColorMap[selected.data.status] ?? "#6b7280" }}
              />
              <span>{selected.data.status}</span>
            </div>

            <div className="mt-4">
              {selected.data.link ? (
                <a
                  href={selected.data.link}
                  target="_blank"
                  className="text-sm text-violet-300 underline underline-offset-2"
                >
                  Open learning page
                </a>
              ) : (
                <p className="text-sm text-slate-400">No page link yet.</p>
              )}
            </div>

            <button
              className="mt-4 rounded-md border border-slate-600 px-3 py-1.5 text-sm hover:bg-slate-800"
              onClick={() => setSelected(null)}
            >
              Close
            </button>
          </aside>
        )}
      </div>
    </div>
  );
}
