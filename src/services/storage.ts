export interface StoragePort { read<T>(key: string): Promise<T | null>; writeAtomic<T>(key: string,value: T): Promise<void>; writeBatchAtomic(records: Record<string,unknown>,remove?: string[]): Promise<void>; remove(key: string): Promise<void> }
interface Envelope { version: 1; payload: string; checksum: string }
const digest=async (payload: string) => [...new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(payload)))].map(value => value.toString(16).padStart(2,'0')).join('');
export class WebStorage implements StoragePort {
  private database: Promise<IDBDatabase>;
  private queue=Promise.resolve();
  constructor() {
    this.database=new Promise((resolve,reject) => {
      const request=indexedDB.open('epoch-rush',1);
      request.onupgradeneeded=() => request.result.createObjectStore('records');
      request.onsuccess=() => resolve(request.result);
      request.onerror=() => reject(request.error);
    });
  }
  async read<T>(key: string): Promise<T | null> {
    const database=await this.database;
    const record=await new Promise<Envelope | undefined>((resolve,reject) => {
      const request=database.transaction('records','readonly').objectStore('records').get(key);
      request.onsuccess=() => resolve(request.result); request.onerror=() => reject(request.error);
    });
    if (!record) return null;
    if (record.version!==1 || await digest(record.payload)!==record.checksum) throw new Error('本地存档校验未通过，原文件已保留');
    return JSON.parse(record.payload) as T;
  }
  writeAtomic<T>(key: string,value: T): Promise<void> {
    return this.writeBatchAtomic({[key]:value});
  }
  writeBatchAtomic(records: Record<string,unknown>,remove: string[]=[]): Promise<void> {
    const payloads=Object.entries(records).map(([key,value])=>({key,payload:JSON.stringify(value)}));
    const operation=this.queue.catch(() => undefined).then(async () => {
      const database=await this.database;
      const envelopes=await Promise.all(payloads.map(async ({key,payload})=>({key,record:{version:1 as const,payload,checksum:await digest(payload)}})));
      await new Promise<void>((resolve,reject) => {
        const transaction=database.transaction('records','readwrite');
        const store=transaction.objectStore('records');
        for(const {key,record} of envelopes) store.put(record,key);
        for(const key of remove) store.delete(key);
        transaction.oncomplete=() => resolve(); transaction.onerror=() => reject(transaction.error); transaction.onabort=() => reject(transaction.error);
      });
    });
    this.queue=operation; return operation;
  }
  async remove(key: string) {
    await this.queue.catch(() => undefined);
    const database=await this.database;
    await new Promise<void>((resolve,reject) => { const transaction=database.transaction('records','readwrite'); transaction.objectStore('records').delete(key); transaction.oncomplete=() => resolve(); transaction.onerror=() => reject(transaction.error); });
  }
}
