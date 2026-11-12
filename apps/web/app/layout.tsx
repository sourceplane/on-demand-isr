import '../styles/globals.css';
import { SITE_NAME } from './site';

export const metadata = {
  title: SITE_NAME,
  description: 'On-demand incremental static regeneration with Next.js, on Cloudflare Workers.',
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
