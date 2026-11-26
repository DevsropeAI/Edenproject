import BrowserDiagnostics from './browser-diagnostics';
import './globals.css';

export const metadata = { title: 'Eden Admin', description: 'Marketplace operations' };

export default function Layout({ children }) {
  return <html lang="en"><body><BrowserDiagnostics/>{children}</body></html>;
}
