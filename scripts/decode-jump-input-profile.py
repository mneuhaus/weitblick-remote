import plistlib, sys
d = plistlib.load(open(sys.argv[1], 'rb'))
objs = d['$objects']
def res(v, depth=0):
    if isinstance(v, plistlib.UID): v = objs[v.data]
    if depth > 12: return '...'
    if isinstance(v, dict):
        if 'NS.objects' in v and 'NS.keys' not in v: return [res(x, depth+1) for x in v['NS.objects']]
        if 'NS.keys' in v: return {res(k, depth+1): res(o, depth+1) for k, o in zip(v['NS.keys'], v['NS.objects'])}
        if '$classes' in v: return None
        out = {}
        for k, x in v.items():
            if k == '$class':
                out['_class'] = objs[x.data]['$classname']; continue
            out[k] = res(x, depth+1)
        return out
    return v
root = res(d['$top']['root']) if 'root' in d['$top'] else res(objs[1])
import json; print(json.dumps(root, indent=1, default=str))
