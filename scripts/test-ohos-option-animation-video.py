import argparse
import json
import subprocess


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--video', required=True)
    parser.add_argument('--region', type=int, nargs=4, required=True, metavar=('X', 'Y', 'WIDTH', 'HEIGHT'))
    parser.add_argument('--start', type=float, required=True)
    parser.add_argument('--end', type=float, required=True)
    parser.add_argument('--ffmpeg', default='ffmpeg')
    args = parser.parse_args()
    left, top, width, height = args.region
    if min(width, height) <= 0 or args.end <= args.start:
        parser.error('Expected a positive region and end > start')
    raw = subprocess.check_output([args.ffmpeg, '-v', 'error', '-ss', str(args.start),
        '-i', args.video, '-t', str(args.end - args.start),
        '-vf', f'fps=30,crop={width}:{height}:{left}:{top}', '-pix_fmt', 'rgb24', '-f', 'rawvideo', '-'])
    pixels = width * height
    stride = pixels * 3
    colors = [[sum(raw[offset + channel:offset + stride:3]) / pixels for channel in range(3)]
              for offset in range(0, len(raw), stride)]
    assert len(colors) >= 5, 'Too few video frames to verify a transition'
    delta = [last - first for first, last in zip(colors[0], colors[-1])]
    length = sum(value * value for value in delta)
    assert length > 1600, 'No substantial selection color change in this region/window'
    progress = [sum((value - first) * change for value, first, change in zip(color, colors[0], delta)) / length for color in colors]
    intermediate = [index for index, value in enumerate(progress) if 0.05 < value < 0.95]
    assert len(intermediate) >= 3, 'Need at least three intermediate frames, not just before/after screenshots'
    print(json.dumps({'video': args.video, 'region': args.region, 'start': args.start, 'end': args.end,
                      'passed': True, 'intermediateFrameCount': len(intermediate),
                      'colors': colors, 'progress': progress}, indent=2))


if __name__ == '__main__':
    main()
