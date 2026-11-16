'use client';

import { useState } from 'react';
import { loadDocument } from './actions';

export function DocumentPreview({ record }) {
  const [document, setDocument] = useState('');
  const [documentError, setDocumentError] = useState('');

  async function preview(kind) {
    setDocument('');
    setDocumentError('');
    try {
      const { image } = await loadDocument(record.id, kind);
      const type = image.startsWith('/9j/') ? 'jpeg' : image.startsWith('iVBOR') ? 'png' : 'webp';
      setDocument('data:image/' + type + ';base64,' + image);
    } catch {
      setDocumentError('Document unavailable.');
    }
  }


  return (
    <div className="record-actions">
          <button type="button" onClick={() => preview('identification')}>View ID</button>
          <button type="button" onClick={() => preview('insurance')}>View insurance</button>
          {document && <img src={document} alt="Submitted verification document" style={{ maxWidth: '100%', maxHeight: 450 }} />}
          {document && <button type="button" onClick={() => setDocument('')}>Close preview</button>}
          {documentError && <span role="status">{documentError}</span>}
        </div>
  );
}
