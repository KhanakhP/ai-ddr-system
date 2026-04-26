def map_images(ddr, images):
    idx = 0

    for obs in ddr.area_wise_observations:
        obs.images = []

        for _ in range(2):
            if idx < len(images):
                obs.images.append(images[idx]["file"])
                idx += 1

    return ddr