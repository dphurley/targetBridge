#include "input_queue.h"

#include <string.h>

static int tb_input_event_is_lossy(enum tb_input_event_kind kind) {
    return kind == TB_INPUT_EVENT_MOVE ||
           kind == TB_INPUT_EVENT_LEFT_DRAG ||
           kind == TB_INPUT_EVENT_RIGHT_DRAG ||
           kind == TB_INPUT_EVENT_OTHER_DRAG ||
           kind == TB_INPUT_EVENT_SCROLL;
}

static size_t tb_input_queue_index(const struct tb_input_queue *queue,
                                   size_t logical_index) {
    return (queue->head + logical_index) % TB_INPUT_QUEUE_CAPACITY;
}

static int tb_input_queue_remove_oldest_lossy(struct tb_input_queue *queue) {
    size_t lossy_index = queue->count;
    for (size_t i = 0; i < queue->count; i++) {
        if (tb_input_event_is_lossy(queue->events[tb_input_queue_index(queue, i)].kind)) {
            lossy_index = i;
            break;
        }
    }
    if (lossy_index == queue->count) return 0;

    for (size_t i = lossy_index; i + 1 < queue->count; i++) {
        queue->events[tb_input_queue_index(queue, i)] =
            queue->events[tb_input_queue_index(queue, i + 1)];
    }
    queue->count--;
    return 1;
}

int tb_input_queue_push(struct tb_input_queue *queue,
                        const struct tb_input_event *event) {
    if (!queue || !event) return 0;

    if (queue->count == TB_INPUT_QUEUE_CAPACITY) {
        if (!tb_input_queue_remove_oldest_lossy(queue)) {
            if (tb_input_event_is_lossy(event->kind)) {
                return 0;
            }

            /* A queue made entirely of lifecycle events cannot safely discard
             * an arbitrary key/button transition. Collapse it to the existing
             * fail-safe command so the Sender releases every held input. */
            memset(queue, 0, sizeof(*queue));
            queue->events[0].kind = TB_INPUT_EVENT_DEACTIVATE_CONTROL;
            queue->count = 1;
            return -1;
        }
    }

    queue->events[tb_input_queue_index(queue, queue->count)] = *event;
    queue->count++;
    return 1;
}

int tb_input_queue_pop(struct tb_input_queue *queue,
                       struct tb_input_event *event) {
    if (!queue || !event || queue->count == 0) return 0;
    *event = queue->events[queue->head];
    queue->head = (queue->head + 1) % TB_INPUT_QUEUE_CAPACITY;
    queue->count--;
    return 1;
}
