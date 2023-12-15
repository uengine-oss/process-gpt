import StorageBaseLocalStorage_ from "./StorageBaseLocalStorage_";

export default class StorageBaseLocalStorage extends StorageBaseLocalStorage_ {
    constructor(client) {
        super(client);
    }
    
    get(path) {
        return this._get(path)
    }

    put(path, string) {
        return this._put(path,string)
    }

    delete(path) {
        return this._delete(path)
    }

    list(path) {
        return this._get(path)
    }

    set(path) {
        return this._put(path)
    }
}
