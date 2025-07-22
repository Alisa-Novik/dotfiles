#!/bin/bash
i3-msg "workspace R2"
pavucontrol &
sleep 0.5
i3-msg '[class="Pavucontrol"] focus'
