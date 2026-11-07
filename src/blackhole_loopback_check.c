#include <CoreAudio/CoreAudio.h>
#include <CoreFoundation/CoreFoundation.h>
#include <errno.h>
#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

/* No recording files. --meter-only does not write to any output buffer.
 * Exit: 0=signal detected, 1=device lookup, 2=format, 3=audio lifecycle,
 *       4=no signal/insufficient data or unexpected test level, 64=arguments.
 */
typedef struct {
    double phase, peak, squares, output_rate;
    uint64_t samples, callbacks, invalid_buffers;
    UInt32 input_channels, output_channels;
    bool tone;
} Meter;

static bool valid_buffers(const AudioBufferList *list, UInt32 channels, UInt32 *frames) {
    if (!list || list->mNumberBuffers == 0) return false;
    UInt32 total_channels = 0;
    UInt32 common_frames = 0;
    for (UInt32 b = 0; b < list->mNumberBuffers; ++b) {
        const AudioBuffer *buffer = &list->mBuffers[b];
        if (!buffer->mData || !buffer->mNumberChannels ||
            buffer->mDataByteSize % (sizeof(float) * buffer->mNumberChannels) != 0) return false;
        UInt32 n = buffer->mDataByteSize / (sizeof(float) * buffer->mNumberChannels);
        if (b && n != common_frames) return false;
        common_frames = n;
        total_channels += buffer->mNumberChannels;
    }
    if (total_channels != channels || !common_frames) return false;
    *frames = common_frames;
    return true;
}

static OSStatus io(AudioDeviceID device, const AudioTimeStamp *now,
    const AudioBufferList *input, const AudioTimeStamp *input_time,
    AudioBufferList *output, const AudioTimeStamp *output_time, void *context) {
    (void)device; (void)now; (void)input_time; (void)output_time;
    Meter *meter = context;
    UInt32 frames = 0;
    if (valid_buffers(input, meter->input_channels, &frames)) {
        for (UInt32 b = 0; b < input->mNumberBuffers; ++b) {
            const AudioBuffer *buffer = &input->mBuffers[b];
            const float *samples = buffer->mData;
            UInt32 count = frames * buffer->mNumberChannels;
            for (UInt32 i = 0; i < count; ++i) {
                double x = samples[i];
                if (!isfinite(x)) { meter->invalid_buffers++; continue; }
                if (fabs(x) > meter->peak) meter->peak = fabs(x);
                meter->squares += x * x;
                meter->samples++;
            }
        }
    } else {
        meter->invalid_buffers++;
    }
    if (meter->tone) {
        if (valid_buffers(output, meter->output_channels, &frames)) {
            double step = 2.0 * M_PI * 440.0 / meter->output_rate;
            // Advance once per frame. Every channel and planar buffer uses the same phase.
            for (UInt32 b = 0; b < output->mNumberBuffers; ++b) {
                AudioBuffer *buffer = &output->mBuffers[b];
                float *samples = buffer->mData;
                double phase = meter->phase;
                for (UInt32 frame = 0; frame < frames; ++frame) {
                    float sample = (float)(0.1 * sin(phase));
                    for (UInt32 channel = 0; channel < buffer->mNumberChannels; ++channel)
                        samples[frame * buffer->mNumberChannels + channel] = sample;
                    phase += step;
                    if (phase >= 2.0 * M_PI) phase -= 2.0 * M_PI;
                }
            }
            meter->phase = fmod(meter->phase + frames * step, 2.0 * M_PI);
        } else {
            meter->invalid_buffers++;
        }
    }
    meter->callbacks++;
    return noErr;
}

static bool read_format(AudioDeviceID device, AudioObjectPropertyScope scope,
                        AudioStreamBasicDescription *format) {
    AudioObjectPropertyAddress address = {
        kAudioDevicePropertyStreamFormat, scope, kAudioObjectPropertyElementMain
    };
    UInt32 size = sizeof(*format);
    OSStatus status = AudioObjectGetPropertyData(device, &address, 0, NULL, &size, format);
    bool valid = !status && size == sizeof(*format) &&
        format->mFormatID == kAudioFormatLinearPCM &&
        (format->mFormatFlags & kAudioFormatFlagIsFloat) &&
        (format->mFormatFlags & kAudioFormatFlagIsPacked) &&
        !(format->mFormatFlags & kAudioFormatFlagIsBigEndian) &&
        format->mBitsPerChannel == 32 && format->mChannelsPerFrame > 0 &&
        isfinite(format->mSampleRate) && format->mSampleRate >= 8000 && format->mSampleRate <= 768000;
    UInt32 samples_per_frame = (format->mFormatFlags & kAudioFormatFlagIsNonInterleaved) ? 1 : format->mChannelsPerFrame;
    valid = valid && format->mBytesPerFrame == sizeof(float) * samples_per_frame;
    if (!valid) fprintf(stderr, "Unsupported %s format: status=%d format=0x%08x flags=0x%08x bits=%u channels=%u rate=%.1f bytes/frame=%u\n",
        scope == kAudioDevicePropertyScopeInput ? "input" : "output", (int)status,
        (unsigned)format->mFormatID, (unsigned)format->mFormatFlags,
        (unsigned)format->mBitsPerChannel, (unsigned)format->mChannelsPerFrame,
        format->mSampleRate, (unsigned)format->mBytesPerFrame);
    return valid;
}

static void usage(FILE *out) {
    fprintf(out, "Usage: blackhole_loopback_check [--meter-only] [--duration SECONDS]\n"
        "  Default: 3 seconds of 440 Hz tone to BlackHole 2ch (amplitude 0.1).\n"
        "  --meter-only: read levels, do not write to output buffers; default 10 seconds.\n"
        "  --duration: finite number from 1 to 120 seconds. No audio files are saved.\n"
        "  Exit 0=signal, 1=device, 2=format, 3=audio API, 4=no/invalid signal, 64=usage.\n");
}

int main(int argc, char **argv) {
    bool meter_only = false;
    double duration = 0;
    for (int i = 1; i < argc; ++i) {
        if (!strcmp(argv[i], "--help") || !strcmp(argv[i], "-h")) { usage(stdout); return 0; }
        if (!strcmp(argv[i], "--meter-only")) { meter_only = true; continue; }
        if (!strcmp(argv[i], "--duration") && i + 1 < argc) {
            char *end = NULL;
            errno = 0;
            duration = strtod(argv[++i], &end);
            if (!errno && end != argv[i] && *end == '\0' && isfinite(duration) && duration >= 1 && duration <= 120) continue;
        }
        usage(stderr);
        return 64;
    }
    if (duration == 0) duration = meter_only ? 10 : 3;
    CFStringRef uid = CFSTR("BlackHole2ch_UID");
    AudioDeviceID device = kAudioObjectUnknown;
    AudioObjectPropertyAddress address = {
        kAudioHardwarePropertyTranslateUIDToDevice, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain
    };
    UInt32 size = sizeof(device);
    OSStatus status = AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, sizeof(uid), &uid, &size, &device);
    if (status || !device) { fprintf(stderr, "BlackHole 2ch lookup failed: status=%d\n", (int)status); return 1; }
    AudioStreamBasicDescription input_format = {0}, output_format = {0};
    if (!read_format(device, kAudioDevicePropertyScopeInput, &input_format)) return 2;
    if (!meter_only && !read_format(device, kAudioDevicePropertyScopeOutput, &output_format)) return 2;
    Meter meter = {0};
    meter.tone = !meter_only;
    meter.input_channels = input_format.mChannelsPerFrame;
    meter.output_channels = output_format.mChannelsPerFrame;
    meter.output_rate = output_format.mSampleRate;
    AudioDeviceIOProcID proc = NULL;
    status = AudioDeviceCreateIOProcID(device, io, &meter, &proc);
    if (status) { fprintf(stderr, "AudioDeviceCreateIOProcID failed: %d\n", (int)status); return 3; }
    status = AudioDeviceStart(device, proc);
    if (status) {
        fprintf(stderr, "AudioDeviceStart failed: %d\n", (int)status);
        AudioDeviceDestroyIOProcID(device, proc);
        return 3;
    }
    struct timespec remaining = { (time_t)duration, (long)((duration - floor(duration)) * 1e9) };
    while (nanosleep(&remaining, &remaining) == -1 && errno == EINTR) {}
    OSStatus stop_status = AudioDeviceStop(device, proc);
    OSStatus destroy_status = AudioDeviceDestroyIOProcID(device, proc);
    if (stop_status || destroy_status) {
        fprintf(stderr, "Audio shutdown failed: stop=%d destroy=%d\n", (int)stop_status, (int)destroy_status);
        return 3;
    }
    double rms = meter.samples ? sqrt(meter.squares / meter.samples) : 0;
    printf("mode=%s device=%u duration=%.3f inputRate=%.1f inputChannels=%u callbacks=%llu samples=%llu invalidBuffers=%llu peak=%.6f rms=%.6f\n",
        meter_only ? "meter-only" : "tone", (unsigned)device, duration,
        input_format.mSampleRate, (unsigned)input_format.mChannelsPerFrame,
        (unsigned long long)meter.callbacks, (unsigned long long)meter.samples,
        (unsigned long long)meter.invalid_buffers, meter.peak, rms);
    bool enough_data = (double)meter.samples >= input_format.mSampleRate * input_format.mChannelsPerFrame * duration * 0.25;
    bool signal = meter_only ? (meter.peak > 0.001 && rms > 0) : (meter.peak > 0.05 && meter.peak < 0.15 && rms > 0.02);
    if (!enough_data || meter.invalid_buffers || !signal) {
        fprintf(stderr, "No usable signal or unexpected test level. Check route, microphone permission and other apps playing to BlackHole.\n");
        return 4;
    }
    return 0;
}
