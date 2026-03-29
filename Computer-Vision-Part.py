import tensorflow as tf
import numpy as np
import cv2

CLASS_NAMES = ['angry', 'contempt', 'disgust', 'fear', 'happy', 'natural', 'sad', 'sleepy', 'surprised']

MODEL_PATH = r"poker_winner_app/lib/best_float32.tflite"


def xywh_to_xyxy(cx, cy, w, h):
    x1 = cx - w / 2
    y1 = cy - h / 2
    x2 = cx + w / 2
    y2 = cy + h / 2
    return [x1, y1, x2, y2]


def iou(box1, box2):
    x1 = max(box1[0], box2[0])
    y1 = max(box1[1], box2[1])
    x2 = min(box1[2], box2[2])
    y2 = min(box1[3], box2[3])

    inter_w = max(0, x2 - x1)
    inter_h = max(0, y2 - y1)
    inter_area = inter_w * inter_h

    area1 = max(0, box1[2] - box1[0]) * max(0, box1[3] - box1[1])
    area2 = max(0, box2[2] - box2[0]) * max(0, box2[3] - box2[1])

    union = area1 + area2 - inter_area
    if union == 0:
        return 0.0

    return inter_area / union


def center_distance(box1_xywh, box2_xywh):
    cx1, cy1, _, _ = box1_xywh
    cx2, cy2, _, _ = box2_xywh
    return ((cx1 - cx2) ** 2 + (cy1 - cy2) ** 2) ** 0.5


def same_face(box1_xywh, box2_xywh, iou_thresh=0.5, center_thresh=0.03):
    box1_xyxy = xywh_to_xyxy(*box1_xywh)
    box2_xyxy = xywh_to_xyxy(*box2_xywh)

    overlap = iou(box1_xyxy, box2_xyxy)
    dist = center_distance(box1_xywh, box2_xywh)

    return overlap >= iou_thresh or dist <= center_thresh


def group_raw_candidates(boxes, class_scores, top_class_scores, keep_thresh=0.01):
    groups = []

    for i in range(len(boxes)):
        if top_class_scores[i] < keep_thresh:
            continue

        box_xywh = boxes[i].tolist()
        score_vector = class_scores[i].tolist()

        matched = False
        for group in groups:
            if same_face(box_xywh, group["box_xywh"]):
                group["detections"].append({
                    "box_xywh": box_xywh,
                    "scores": score_vector
                })
                matched = True
                break

        if not matched:
            groups.append({
                "box_xywh": box_xywh,
                "detections": [{
                    "box_xywh": box_xywh,
                    "scores": score_vector
                }]
            })

    return groups


def weighted_emotion_scores(group):
    weights = [1.0, 0.5, 0.25]
    final_scores = []

    for emotion_idx in range(len(CLASS_NAMES)):
        vals = []

        for det in group["detections"]:
            vals.append(det["scores"][emotion_idx])

        vals.sort(reverse=True)
        vals = vals[:3]

        total = 0.0
        for i, val in enumerate(vals):
            total += weights[i] * val

        score = total / 1.75   # fixed denominator to reward repeated evidence
        final_scores.append(score)

    return final_scores


def main(IMAGE_PATH):
    interpreter = tf.lite.Interpreter(model_path=MODEL_PATH)
    interpreter.allocate_tensors()

    input_details = interpreter.get_input_details()
    output_details = interpreter.get_output_details()

    img = cv2.imread(IMAGE_PATH)
    img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
    img = cv2.resize(img, (640, 640))
    img = img.astype(np.float32) / 255.0
    img = np.expand_dims(img, axis=0)

    interpreter.set_tensor(input_details[0]["index"], img)
    interpreter.invoke()

    output = interpreter.get_tensor(output_details[0]["index"]) 
    preds = output[0].T                                          

    boxes = preds[:, :4]
    class_scores = preds[:, 4:]                                

    top_class_scores = np.max(class_scores, axis=1)

    groups = group_raw_candidates(boxes, class_scores, top_class_scores, keep_thresh=0.01)

    print(f"Number of face groups: {len(groups)}")

    for i, group in enumerate(groups, start=1):
        scores = weighted_emotion_scores(group)
        top_idx = int(np.argmax(scores))
        top_emotion = CLASS_NAMES[top_idx]

        print(f"\n===== Face Group {i} =====")
        print("Representative box:", [round(x, 6) for x in group["box_xywh"]])
        print("Detections in group:", len(group["detections"]))
        print("Scores:")

        for j, emotion in enumerate(CLASS_NAMES):
            print(f"  {emotion}: {scores[j]:.6f}")

        print("Top emotion:", top_emotion)


if __name__ == "__main__":
    IMAGE_PATH = r"C:\Users\Phillip\Desktop\coding projects\build4good2026\Poker-Winner-3000\ds\9 Facial Expressions you need\test\images\xavi-cabrera-_-uN7DbAE-o-unsplash_jpg.rf.11bf800ee0f78d2e3c1c43191aa9ba89.jpg"
    main(IMAGE_PATH)