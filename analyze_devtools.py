import json

def read_varint(data, pos):
    val = 0
    shift = 0
    while True:
        b = data[pos]
        pos += 1
        val |= (b & 0x7F) << shift
        if not (b & 0x80):
            break
        shift += 7
    return val, pos

def parse_proto(data, start, end):
    pos = start
    fields = []
    while pos < end:
        try:
            key, pos = read_varint(data, pos)
        except IndexError:
            break
        field_num = key >> 3
        wire_type = key & 0x07
        
        if wire_type == 0:
            val, pos = read_varint(data, pos)
            fields.append((field_num, wire_type, val))
        elif wire_type == 1:
            if pos + 8 > end:
                break
            val = data[pos:pos+8]
            pos += 8
            fields.append((field_num, wire_type, val))
        elif wire_type == 2:
            length, pos = read_varint(data, pos)
            if pos + length > end:
                break
            val = data[pos:pos+length]
            pos += length
            fields.append((field_num, wire_type, val))
        elif wire_type == 5:
            if pos + 4 > end:
                break
            val = data[pos:pos+4]
            pos += 4
            fields.append((field_num, wire_type, val))
        else:
            break
    return fields, pos

def print_tree(roots, max_depth=15):
    def print_node(node, indent=0):
        if indent > max_depth:
            return
        dur_str = f"{node.get('dur', 0.0):.2f}ms" if node.get('end') is not None else "running..."
        print(f"{'  ' * indent}- {node['name']} ({node['category']}): {dur_str}")
        valid_children = [c for c in node['children'] if c.get('dur', 0.0) > 0.1]
        for child in sorted(valid_children, key=lambda x: x.get('dur', 0.0), reverse=True):
            print_node(child, indent + 1)
            
    for r in roots:
        if r.get('dur', 0.0) > 0.1:
            print_node(r)

def main():
    filepath = "/Users/axel10/Downloads/dart_devtools_2026-07-08_16_51_24.408.json"
    with open(filepath, 'r') as f:
        data = json.load(f)
    
    perf = data.get('performance', {})
    tb = perf.get('traceBinary')
    if not tb:
        print("No traceBinary found")
        return
        
    pos = 0
    end = len(tb)
    packets = []
    
    while pos < end:
        if pos + 1 > end:
            break
        key, next_pos = read_varint(tb, pos)
        field_num = key >> 3
        wire_type = key & 0x07
        
        if field_num == 1 and wire_type == 2:
            length, next_pos = read_varint(tb, next_pos)
            if next_pos + length > end:
                break
            packets.append(tb[next_pos:next_pos+length])
            pos = next_pos + length
        else:
            if wire_type == 0:
                _, pos = read_varint(tb, next_pos)
            elif wire_type == 1:
                pos = next_pos + 8
            elif wire_type == 2:
                length, pos = read_varint(tb, next_pos)
                pos = pos + length
            elif wire_type == 5:
                pos = next_pos + 4
            else:
                break

    UI_THREAD_UUID = 538676805912
    
    raw_events = []
    for pkt in packets:
        fields, _ = parse_proto(pkt, 0, len(pkt))
        ts = None
        evt_fields = None
        for f_num, w_type, val in fields:
            if f_num == 8:
                ts = val
            elif f_num == 11:
                evt_fields, _ = parse_proto(val, 0, len(val))
                
        if ts is not None and evt_fields is not None:
            track_uuid = None
            evt_type = None
            name = None
            category = None
            for ef_num, ew_type, val_bytes in evt_fields:
                if ef_num == 11:
                    track_uuid = val_bytes
                elif ef_num == 9:
                    evt_type = val_bytes
                elif ef_num == 23:
                    name = bytes(val_bytes).decode('utf-8', errors='replace')
                elif ef_num == 22:
                    category = bytes(val_bytes).decode('utf-8', errors='replace')
            
            if track_uuid == UI_THREAD_UUID:
                raw_events.append({
                    "ts_us": ts / 1000.0,
                    "type": evt_type,
                    "name": name,
                    "category": category
                })
                
    raw_events.sort(key=lambda x: x['ts_us'])
    
    # Get slow build frames
    frames = perf.get('flutterFrames', [])
    # Filter frames that have build > 15ms and fall within raw_events time range
    min_event_ts = min(e['ts_us'] for e in raw_events) if raw_events else 0
    max_event_ts = max(e['ts_us'] for e in raw_events) if raw_events else 0
    
    candidate_frames = [f for f in frames if f.get('build', 0) > 15000 and f['startTime'] >= min_event_ts and f['startTime'] <= max_event_ts]
    # Sort candidate frames by build time desc
    candidate_frames.sort(key=lambda x: x.get('build', 0), reverse=True)
    
    print(f"Total candidate frames in event range: {len(candidate_frames)}")
    
    for f in candidate_frames[:3]:
        frame_num = f.get('number')
        frame_start = f['startTime']
        frame_end = f['startTime'] + f['elapsed']
        build_ms = f['build'] / 1000.0
        elapsed_ms = f['elapsed'] / 1000.0
        
        frame_events = [ev for ev in raw_events if ev['ts_us'] >= frame_start and ev['ts_us'] <= frame_end]
        print(f"\n==================================================")
        print(f"Analyzing Frame #{frame_num}: Build = {build_ms:.2f}ms, Elapsed = {elapsed_ms:.2f}ms")
        print(f"Collected {len(frame_events)} UI events.")
        
        stack = []
        roots = []
        for ev in frame_events:
            if ev['type'] == 1: # Begin
                node = {
                    "name": ev['name'] or "unknown",
                    "category": ev['category'],
                    "start": ev['ts_us'],
                    "end": None,
                    "children": []
                }
                if stack:
                    stack[-1]['children'].append(node)
                else:
                    roots.append(node)
                stack.append(node)
            elif ev['type'] == 2: # End
                if stack:
                    node = stack.pop()
                    node['end'] = ev['ts_us']
                    node['dur'] = (ev['ts_us'] - node['start']) / 1000.0
        
        print(f"UI Thread Slice Hierarchy for Frame #{frame_num} (slices > 0.5ms):")
        print_tree(roots)

if __name__ == "__main__":
    main()
