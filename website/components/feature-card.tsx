import type { ReactNode } from 'react';

import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';

export function FeatureCard({
  title,
  description,
  icon,
}: {
  title: string;
  description: string;
  icon: ReactNode;
}) {
  return (
    <Card className="border border-white/8 bg-slate-900/60 py-1 shadow-xl shadow-black/10 ring-0">
      <CardHeader className="px-6 pt-6">
        <div className="mb-5 flex size-11 items-center justify-center rounded-xl border border-cyan-300/15 bg-cyan-300/8 text-cyan-300 [&_svg]:size-5">
          {icon}
        </div>
        <CardTitle className="text-lg font-semibold tracking-[-0.02em] text-white">
          {title}
        </CardTitle>
      </CardHeader>
      <CardContent className="px-6 pb-6 text-sm leading-6 text-slate-400">
        {description}
      </CardContent>
    </Card>
  );
}
