// Simple iPhone holder base plate.
// Units: millimeters.

length = 100;
width = 80;
height = 3;
back_corner_radius = 30;
back_corner_steps = 16;

// Front wall for the holder of the phone
front_wall_thickness = 3;
front_wall_width = 78;
front_wall_height = 55;
front_wall_angle = 7;
front_wall_text = "VOZHYK";
front_wall_text_size = 10;
front_wall_text_depth = 0.8;
side_wall_depth = 17;
side_wall_thickness = 3;
rear_wall_thickness = 3;
rear_wall_height = 40;

// ESP32 block
pillar_diameter = 2;
pillar_height = 17;
pillar_x_spacing = 23.5;
pillar_y_spacing = 46;
pillar_distance_from_rear_wall = 10;
pillar_first_row_x = side_wall_depth + pillar_distance_from_rear_wall;
pillar_center_y = width / 2;
pillar_box_clearance = 3;
pillar_box_wall_width = 2;
pillar_box_height = 22;
pillar_box_inner_length = pillar_x_spacing + pillar_box_clearance * 2;
pillar_box_inner_width = pillar_y_spacing + pillar_box_clearance * 2;
pillar_box_outer_length = pillar_box_inner_length + pillar_box_wall_width * 2;
pillar_box_outer_width = pillar_box_inner_width + pillar_box_wall_width * 2;
pillar_box_origin_x = pillar_first_row_x - pillar_box_clearance - pillar_box_wall_width;
pillar_box_origin_y = pillar_center_y - pillar_y_spacing / 2 - pillar_box_clearance - pillar_box_wall_width;

// ESP32 USB type C
pillar_box_slot_width = 9;
pillar_box_slot_height = 3.5;
pillar_box_slot_top_offset = 2;

// servo SG90 section
rear_center_plate_width = 11.5;
rear_center_plate_length = 22.5;
rear_center_plate_height = 1;
rear_center_plate_back_offset = 7;
rear_center_plate_origin_x = length - rear_center_plate_back_offset - rear_center_plate_length;
rear_center_plate_origin_y = (width - rear_center_plate_width) / 2;
servo_plate_box_wall_width = 2;
servo_plate_box_height = 4.5;
servo_plate_side_block_width = 4;
servo_plate_side_block_hole_diameter = 2;
servo_plate_box_origin_x = rear_center_plate_origin_x - servo_plate_box_wall_width;
servo_plate_box_origin_y = rear_center_plate_origin_y - servo_plate_box_wall_width;
servo_plate_box_outer_length = rear_center_plate_length + servo_plate_box_wall_width * 2;
servo_plate_box_outer_width = rear_center_plate_width + servo_plate_box_wall_width * 2;
servo_plate_side_block_hole_y = servo_plate_box_origin_y + servo_plate_box_outer_width / 2;
servo_plate_side_block_hole_front_x = servo_plate_box_origin_x - servo_plate_side_block_width / 2;
servo_plate_side_block_hole_back_x =
    servo_plate_box_origin_x + servo_plate_box_outer_length + servo_plate_side_block_width / 2;
servo_hole_diameter = 11.5;
servo_hole_center_x = length - rear_center_plate_back_offset - servo_hole_diameter / 2;
servo_hole_center_y = width / 2;
servo_small_hole_diameter = 7;
servo_small_hole_center_distance = 7;
servo_small_hole_center_x = servo_hole_center_x - servo_small_hole_center_distance;
servo_small_hole_center_y = servo_hole_center_y;
$fn = 32;

module base_plate() {
    linear_extrude(height = height)
        polygon(points = concat(
            [[0, 0], [length - back_corner_radius, 0]],
            [
                for (i = [0:back_corner_steps])
                    [
                        length - back_corner_radius
                            + back_corner_radius * sin(i * 90 / back_corner_steps),
                        back_corner_radius
                            - back_corner_radius * cos(i * 90 / back_corner_steps)
                    ]
            ],
            [[length, width - back_corner_radius]],
            [
                for (i = [0:back_corner_steps])
                    [
                        length - back_corner_radius
                            + back_corner_radius * cos(i * 90 / back_corner_steps),
                        width - back_corner_radius
                            + back_corner_radius * sin(i * 90 / back_corner_steps)
                    ]
            ],
            [[0, width]]
        ));
}

module front_wall_label() {
    translate([0, (width - front_wall_width) / 2, height])
        rotate([0, front_wall_angle, 0])
        translate([-front_wall_text_depth, front_wall_width / 2, front_wall_height * 0.58])
        rotate([90, 0, 90])
        linear_extrude(height = front_wall_text_depth)
            mirror([1, 0, 0])
            text(
                front_wall_text,
                size = front_wall_text_size,
                halign = "center",
                valign = "center",
                font = "Liberation Sans:style=Bold"
            );
}

difference() {
    union() {
        base_plate();

        translate([0, (width - front_wall_width) / 2, height])
            rotate([0, front_wall_angle, 0])
            cube([front_wall_thickness, front_wall_width, front_wall_height], center = false);

        front_wall_label();

        translate([0, (width - front_wall_width) / 2, height])
            rotate([0, front_wall_angle, 0])
            cube([side_wall_depth, side_wall_thickness, front_wall_height], center = false);

        translate([0, (width + front_wall_width) / 2 - side_wall_thickness, height])
            rotate([0, front_wall_angle, 0])
            cube([side_wall_depth, side_wall_thickness, front_wall_height], center = false);

        translate([0, (width - front_wall_width) / 2, height])
            rotate([0, front_wall_angle, 0])
            translate([side_wall_depth - rear_wall_thickness, 0, 0])
            cube([rear_wall_thickness, front_wall_width, rear_wall_height], center = false);

        for (x = [pillar_first_row_x, pillar_first_row_x + pillar_x_spacing]) {
            for (y = [pillar_center_y - pillar_y_spacing / 2, pillar_center_y + pillar_y_spacing / 2]) {
                translate([x, y, height])
                    cylinder(h = pillar_height, d = pillar_diameter, center = false);
            }
        }

        translate([pillar_box_origin_x, pillar_box_origin_y, height])
            difference() {
                cube([pillar_box_outer_length, pillar_box_outer_width, pillar_box_height], center = false);
                translate([pillar_box_wall_width, pillar_box_wall_width, -0.1])
                    cube([pillar_box_inner_length, pillar_box_inner_width, pillar_box_height + 0.2], center = false);
                translate([
                    (pillar_box_outer_length - pillar_box_slot_width) / 2,
                    -0.1,
                    pillar_box_height - pillar_box_slot_top_offset - pillar_box_slot_height
                ])
                    cube([pillar_box_slot_width, pillar_box_wall_width + 0.2, pillar_box_slot_height], center = false);
            }

        translate([
            rear_center_plate_origin_x,
            rear_center_plate_origin_y,
            height
        ])
            cube([rear_center_plate_length, rear_center_plate_width, rear_center_plate_height], center = false);

        translate([
            servo_plate_box_origin_x,
            servo_plate_box_origin_y,
            height
        ])
            difference() {
                cube([
                    servo_plate_box_outer_length,
                    servo_plate_box_outer_width,
                    servo_plate_box_height
                ], center = false);
                translate([servo_plate_box_wall_width, servo_plate_box_wall_width, -0.1])
                    cube([
                        rear_center_plate_length,
                        rear_center_plate_width,
                        servo_plate_box_height + 0.2
                    ], center = false);
            }

        translate([
            servo_plate_box_origin_x - servo_plate_side_block_width,
            servo_plate_box_origin_y,
            height
        ])
            cube([
                servo_plate_side_block_width,
                servo_plate_box_outer_width,
                servo_plate_box_height
            ], center = false);

        translate([
            servo_plate_box_origin_x + servo_plate_box_outer_length,
            servo_plate_box_origin_y,
            height
        ])
            cube([
                servo_plate_side_block_width,
                servo_plate_box_outer_width,
                servo_plate_box_height
            ], center = false);
    }

    translate([servo_hole_center_x, servo_hole_center_y, -0.1])
        cylinder(
            h = height + rear_center_plate_height + servo_plate_box_height + 0.2,
            d = servo_hole_diameter,
            center = false
        );

    translate([servo_small_hole_center_x, servo_small_hole_center_y, -0.1])
        cylinder(
            h = height + rear_center_plate_height + servo_plate_box_height + 0.2,
            d = servo_small_hole_diameter,
            center = false
        );

    translate([
        servo_plate_side_block_hole_front_x,
        servo_plate_side_block_hole_y,
        height - 0.1
    ])
        cylinder(
            h = servo_plate_box_height + 0.2,
            d = servo_plate_side_block_hole_diameter,
            center = false
        );

    translate([
        servo_plate_side_block_hole_back_x,
        servo_plate_side_block_hole_y,
        height - 0.1
    ])
        cylinder(
            h = servo_plate_box_height + 0.2,
            d = servo_plate_side_block_hole_diameter,
            center = false
        );
}
