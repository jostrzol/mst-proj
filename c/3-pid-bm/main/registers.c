#include <math.h>

#include "registers.h"

regs_t regs_create() {
  return (regs_t){
      .input =
          {
              .frequency = 0,
              .control_signal = 0,
          },
      .holding =
          {
              .target_frequency = 0,
              .proportional_factor = 0,
              .integration_time = INFINITY,
              .differentiation_time = 0,
          },
  };
}
